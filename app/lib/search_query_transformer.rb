# frozen_string_literal: true

class SearchQueryTransformer < Parslet::Transform
  SUPPORTED_PREFIXES = %w(
    has
    is
    language
    from
    before
    after
    during
    in
  ).freeze

  POLL_OPTIONS_TSV_EXPRESSION = "to_tsvector('simple'::regconfig, array_to_string(polls.options, ' '::text))"
  MEDIA_ATTACHMENTS_DESCRIPTION_TSV_EXPRESSION = "to_tsvector('simple'::regconfig, COALESCE(media_attachments.description, ''::text))"

  def self.tsquery_tokens(text)
    text.to_s.scan(/[\p{L}\p{N}_]+/)
  end

  def self.to_prefix_tsquery(text)
    tokens = tsquery_tokens(text)
    return if tokens.empty?

    tokens.map { |token| "#{token}:*" }.join(' & ')
  end

  def self.to_phrase_tsquery(text)
    tokens = tsquery_tokens(text)
    return if tokens.empty?

    last = tokens.pop
    (tokens + ["#{last}:*"]).join(' <-> ')
  end

  def self.database_text_condition
    <<~SQL.squish
      statuses.tsv @@ to_tsquery('simple', :tsquery)
      OR EXISTS (
        SELECT 1 FROM polls
        WHERE polls.id = statuses.poll_id
          AND #{POLL_OPTIONS_TSV_EXPRESSION} @@ to_tsquery('simple', :tsquery)
      )
      OR EXISTS (
        SELECT 1 FROM media_attachments
        WHERE media_attachments.status_id = statuses.id
          AND #{MEDIA_ATTACHMENTS_DESCRIPTION_TSV_EXPRESSION} @@ to_tsquery('simple', :tsquery)
      )
    SQL
  end

  class Query
    def initialize(clauses, options = {})
      raise ArgumentError if options[:current_account].nil?

      @clauses = clauses
      @options = options

      flags_from_clauses!
    end

    def request
      search = Chewy::Search::Request.new(*indexes).filter(default_filter)

      must_clauses.each { |clause| search = search.query.must(clause.to_query) }
      must_not_clauses.each { |clause| search = search.query.must_not(clause.to_query) }
      filter_clauses.each { |clause| search = search.filter(**clause.to_query) }

      search
    end

    def database_scope
      return Status.none if content_clauses.empty? && filter_clauses.empty? && @flags.empty?

      scope = base_database_scope

      must_clauses.each { |clause| scope = clause.apply(scope) }
      must_not_clauses.each { |clause| scope = clause.apply(scope) }
      filter_clauses.each { |clause| scope = clause.apply(scope) }

      scope
    end

    private

    def clauses_by_operator
      @clauses_by_operator ||= @clauses.compact.group_by(&:operator)
    end

    def flags_from_clauses!
      @flags = clauses_by_operator.fetch(:flag, []).to_h { |clause| [clause.prefix, clause.term] }
    end

    def must_clauses
      clauses_by_operator.fetch(:must, [])
    end

    def must_not_clauses
      clauses_by_operator.fetch(:must_not, [])
    end

    def filter_clauses
      clauses_by_operator.fetch(:filter, [])
    end

    def content_clauses
      must_clauses + must_not_clauses
    end

    def base_database_scope
      scope = Status.unscoped.kept.without_reblogs

      case @flags['in']
      when 'library'
        sql, binds = library_conditions
        scope = scope.where(sql, binds)
      when 'public'
        sql, binds = public_conditions
        scope = scope.where(sql, binds)
      else
        library_sql, library_binds = library_conditions
        public_sql, public_binds = public_conditions
        scope = scope.where("(#{public_sql}) OR (#{library_sql})", public_binds.merge(library_binds))
      end

      scope.order(id: :desc)
    end

    def public_conditions
      [
        'statuses.visibility = :public_visibility AND EXISTS (SELECT 1 FROM accounts WHERE accounts.id = statuses.account_id AND accounts.indexable = TRUE)',
        { public_visibility: Status.visibilities[:public] },
      ]
    end

    def library_conditions
      sql = <<~SQL.squish
        (statuses.account_id = :current_account_id AND (statuses.local = TRUE OR statuses.uri IS NULL))
        OR EXISTS (SELECT 1 FROM mentions WHERE mentions.status_id = statuses.id AND mentions.account_id = :current_account_id AND mentions.silent = FALSE)
        OR EXISTS (SELECT 1 FROM favourites WHERE favourites.status_id = statuses.id AND favourites.account_id = :current_account_id)
        OR EXISTS (SELECT 1 FROM bookmarks WHERE bookmarks.status_id = statuses.id AND bookmarks.account_id = :current_account_id)
        OR EXISTS (SELECT 1 FROM poll_votes WHERE poll_votes.poll_id = statuses.poll_id AND poll_votes.account_id = :current_account_id)
        OR EXISTS (SELECT 1 FROM statuses reblogs WHERE reblogs.reblog_of_id = statuses.id AND reblogs.account_id = :current_account_id AND reblogs.deleted_at IS NULL)
      SQL

      [sql, { current_account_id: @options[:current_account].id }]
    end

    def indexes
      case @flags['in']
      when 'library'
        [StatusesIndex]
      when 'public'
        [PublicStatusesIndex]
      else
        [PublicStatusesIndex, StatusesIndex]
      end
    end

    def default_filter
      {
        bool: {
          should: [
            {
              term: {
                _index: PublicStatusesIndex.index_name,
              },
            },
            {
              bool: {
                must: [
                  {
                    term: {
                      _index: StatusesIndex.index_name,
                    },
                  },
                  {
                    term: {
                      searchable_by: @options[:current_account].id,
                    },
                  },
                ],
              },
            },
          ],

          minimum_should_match: 1,
        },
      }
    end
  end

  class Operator
    class << self
      def symbol(str)
        case str
        when '+', nil
          :must
        when '-'
          :must_not
        else
          raise "Unknown operator: #{str}"
        end
      end
    end
  end

  class TermClause
    attr_reader :operator, :term

    def initialize(operator, term)
      @operator = Operator.symbol(operator)
      @term = term
    end

    def to_query
      if @term.start_with?('#')
        { match: { tags: { query: @term, operator: 'and' } } }
      else
        { multi_match: { type: 'most_fields', query: @term, fields: ['text', 'text.stemmed'], operator: 'and' } }
      end
    end

    def apply(scope)
      if @term.start_with?('#')
        tag = @term.delete_prefix('#')
        condition = 'EXISTS (SELECT 1 FROM statuses_tags st JOIN tags t ON t.id = st.tag_id WHERE st.status_id = statuses.id AND LOWER(t.name) = LOWER(?))'
        @operator == :must_not ? scope.where.not(condition, tag) : scope.where(condition, tag)
      else
        tsquery = SearchQueryTransformer.to_prefix_tsquery(@term)
        return scope if tsquery.nil?

        condition = SearchQueryTransformer.database_text_condition
        @operator == :must_not ? scope.where("NOT (#{condition})", tsquery: tsquery) : scope.where(condition, tsquery: tsquery)
      end
    end
  end

  class PhraseClause
    attr_reader :operator, :phrase

    def initialize(operator, phrase)
      @operator = Operator.symbol(operator)
      @phrase = phrase
    end

    def to_query
      { match_phrase: { text: { query: @phrase } } }
    end

    def apply(scope)
      tsquery = SearchQueryTransformer.to_phrase_tsquery(@phrase)
      return scope if tsquery.nil?

      condition = SearchQueryTransformer.database_text_condition
      @operator == :must_not ? scope.where("NOT (#{condition})", tsquery: tsquery) : scope.where(condition, tsquery: tsquery)
    end
  end

  class PrefixClause
    EPOCH_RE = /\A\d+\z/

    PROPERTY_CONDITIONS = {
      'media' => 'EXISTS (SELECT 1 FROM media_attachments WHERE media_attachments.status_id = statuses.id)',
      'image' => "EXISTS (SELECT 1 FROM media_attachments WHERE media_attachments.status_id = statuses.id AND media_attachments.file_content_type LIKE 'image/%')",
      'video' => "EXISTS (SELECT 1 FROM media_attachments WHERE media_attachments.status_id = statuses.id AND media_attachments.file_content_type LIKE 'video/%')",
      'audio' => "EXISTS (SELECT 1 FROM media_attachments WHERE media_attachments.status_id = statuses.id AND media_attachments.file_content_type LIKE 'audio/%')",
      'poll' => 'statuses.poll_id IS NOT NULL',
      'link' => 'EXISTS (SELECT 1 FROM preview_cards_statuses WHERE preview_cards_statuses.status_id = statuses.id)',
      'sensitive' => 'statuses.sensitive = TRUE',
      'reply' => 'statuses.reply = TRUE',
      'quote' => 'EXISTS (SELECT 1 FROM quotes WHERE quotes.status_id = statuses.id)',
    }.freeze

    attr_reader :operator, :prefix, :term

    def initialize(prefix, operator, term, options = {})
      @prefix = prefix
      @raw_term = term
      @negated = operator == '-'
      @options = options
      @operator = :filter

      case prefix
      when 'has', 'is'
        @filter = :properties
        @type = :term
        @term = term
      when 'language'
        @filter = :language
        @type = :term
        @term = language_code_from_term(term)
      when 'from'
        @filter = :account_id
        @type = :term
        @term = account_id_from_term(term)
      when 'before'
        @filter = :created_at
        @type = :range
        @term = { lt: date_from_term(term), time_zone: @options[:current_account]&.user_time_zone.presence || 'UTC' }
      when 'after'
        @filter = :created_at
        @type = :range
        @term = { gt: date_from_term(term), time_zone: @options[:current_account]&.user_time_zone.presence || 'UTC' }
      when 'during'
        @filter = :created_at
        @type = :range
        @term = { gte: date_from_term(term), lte: date_from_term(term), time_zone: @options[:current_account]&.user_time_zone.presence || 'UTC' }
      when 'in'
        @operator = :flag
        @term = term
      else
        raise "Unknown prefix: #{prefix}"
      end
    end

    def to_query
      if @negated
        { bool: { must_not: { @type => { @filter => @term } } } }
      else
        { @type => { @filter => @term } }
      end
    end

    def apply(scope)
      return scope if @operator == :flag

      sql, *binds = database_condition
      return scope if sql.nil?

      @negated ? scope.where.not(sql, *binds) : scope.where(sql, *binds)
    end

    private

    def database_condition
      case @prefix
      when 'has', 'is'
        property_condition
      when 'language'
        ['statuses.language = ?', @term]
      when 'from'
        ['statuses.account_id = ?', @term]
      when 'before'
        ['statuses.created_at < ?', parse_date(@raw_term)]
      when 'after'
        ['statuses.created_at > ?', parse_date(@raw_term)]
      when 'during'
        date = parse_date(@raw_term)
        ['statuses.created_at >= ? AND statuses.created_at < ?', date, date + 1.day]
      end
    end

    def property_condition
      case @raw_term.to_s.downcase
      when 'embed'
        ['EXISTS (SELECT 1 FROM preview_cards_statuses pcs JOIN preview_cards pc ON pc.id = pcs.preview_card_id WHERE pcs.status_id = statuses.id AND pc.type = ?)', PreviewCard.types[:video]]
      else
        [PROPERTY_CONDITIONS.fetch(@raw_term.to_s.downcase, '1=0')]
      end
    end

    def parse_date(term)
      return Time.zone.at(term.to_i) if term.match?(EPOCH_RE)

      DateTime.iso8601(term)
    end

    def account_id_from_term(term)
      return @options[:current_account]&.id || -1 if term == 'me'

      username, domain = term.gsub(/\A@/, '').split('@')
      domain = nil if TagManager.instance.local_domain?(domain)
      account = Account.find_remote(username, domain)

      # If the account is not found, we want to return empty results, so return
      # an ID that does not exist
      account&.id || -1
    end

    def language_code_from_term(term)
      language_code = term

      return language_code if LanguagesHelper::SUPPORTED_LOCALES.key?(language_code.to_sym)

      language_code = term.downcase

      return language_code if LanguagesHelper::SUPPORTED_LOCALES.key?(language_code.to_sym)

      language_code = term.split(/[_-]/).first.downcase

      return language_code if LanguagesHelper::SUPPORTED_LOCALES.key?(language_code.to_sym)

      term
    end

    def date_from_term(term)
      DateTime.iso8601(term) unless term.match?(EPOCH_RE) # This will raise Date::Error if the date is invalid
      term
    end
  end

  rule(clause: subtree(:clause)) do
    prefix   = clause[:prefix][:term].to_s.downcase if clause[:prefix]
    operator = clause[:operator]&.to_s
    term     = clause[:phrase] ? clause[:phrase].map { |term| term[:term].to_s }.join(' ') : clause[:term].to_s

    if clause[:prefix] && SUPPORTED_PREFIXES.include?(prefix)
      PrefixClause.new(prefix, operator, term, current_account: current_account)
    elsif clause[:prefix]
      TermClause.new(operator, "#{prefix} #{term}")
    elsif clause[:term]
      TermClause.new(operator, term)
    elsif clause[:phrase]
      PhraseClause.new(operator, term)
    else
      raise "Unexpected clause type: #{clause}"
    end
  end

  rule(junk: subtree(:junk)) do
    nil
  end

  rule(query: sequence(:clauses)) do
    Query.new(clauses, current_account: current_account)
  end
end
