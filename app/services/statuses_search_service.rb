# frozen_string_literal: true

class StatusesSearchService < BaseService
  def self.database_backend_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('DB_SEARCH_ENABLED', 'true'))
  end

  def self.database_backend_available?
    return false unless database_backend_enabled?

    Status.columns_hash.key?('tsv')
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    false
  end

  def self.backend_available?
    Chewy.enabled? || database_backend_available?
  end

  def call(query, account = nil, options = {})
    MastodonOTELTracer.in_span('StatusesSearchService#call') do |span|
      @query   = query&.strip
      @account = account
      @options = options
      @limit   = options[:limit].to_i
      @offset  = options[:offset].to_i
      convert_deprecated_options!

      span.add_attributes(
        'search.offset' => @offset,
        'search.limit' => @limit,
        'search.backend' => search_backend
      )

      status_search_results.tap do |results|
        span.set_attribute('search.results.count', results.size)
      end
    end
  end

  private

  def status_search_results
    results = fetch_results
    return [] if results.empty?

    account_ids         = results.map(&:account_id)
    account_domains     = results.map(&:account_domain)
    preloaded_relations = @account.relations_map(account_ids, account_domains)

    results.reject { |status| StatusFilter.new(status, @account, preloaded_relations).filtered? }
  rescue Faraday::ConnectionFailed, Parslet::ParseFailed, Errno::ENETUNREACH
    []
  end

  def fetch_results
    if Chewy.enabled?
      elasticsearch_results
    elsif self.class.database_backend_available?
      database_results
    else
      []
    end
  end

  def search_backend
    if Chewy.enabled?
      'elasticsearch'
    elsif self.class.database_backend_available?
      'database'
    else
      'disabled'
    end
  end

  def elasticsearch_results
    parsed_query.request.collapse(field: :id).order(id: { order: :desc }).limit(@limit).offset(@offset).objects.compact
  end

  def database_results
    parsed_query.database_scope.limit(@limit).offset(@offset).includes(:account).to_a
  end

  def parsed_query
    SearchQueryTransformer.new.apply(SearchQueryParser.new.parse(@query), current_account: @account)
  end

  def convert_deprecated_options!
    syntax_options = []

    if @options[:account_id]
      username = Account.select(:username, :domain).find(@options[:account_id]).acct
      syntax_options << "from:@#{username}"
    end

    if @options[:min_id]
      timestamp = Mastodon::Snowflake.to_time(@options[:min_id].to_i)
      syntax_options << "after:\"#{timestamp.iso8601}\""
    end

    if @options[:max_id]
      timestamp = Mastodon::Snowflake.to_time(@options[:max_id].to_i)
      syntax_options << "before:\"#{timestamp.iso8601}\""
    end

    @query = "#{@query} #{syntax_options.join(' ')}".strip if syntax_options.any?
  end
end
