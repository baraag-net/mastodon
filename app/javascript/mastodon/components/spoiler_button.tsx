import { FormattedMessage } from 'react-intl';

import classNames from 'classnames';

import { me } from 'mastodon/initial_state';

interface Props {
  hidden?: boolean;
  sensitive: boolean;
  uncached?: boolean;
  matchedFilters?: string[];
  onClick: React.MouseEventHandler<HTMLButtonElement>;
}

export const SpoilerButton: React.FC<Props> = ({
  hidden = false,
  sensitive,
  uncached = false,
  matchedFilters,
  onClick,
}) => {
  let warning;
  let action;

  const showAction = me ? (
    <FormattedMessage id='status.media.show' defaultMessage='Click to show' />
  ) : (
    <FormattedMessage
      id='status.media.show_logged_out'
      defaultMessage='By clicking, you affirm to be 18+ or older'
    />
  );

  if (uncached) {
    warning = (
      <FormattedMessage
        id='status.uncached_media_warning'
        defaultMessage='Preview not available'
      />
    );
    action = (
      <FormattedMessage id='status.media.open' defaultMessage='Click to open' />
    );
  } else if (matchedFilters?.length) {
    warning = (
      <FormattedMessage
        id='filter_warning.matches_filter'
        defaultMessage='Matches filter “<span>{title}</span>”'
        values={{
          title: matchedFilters.join(', '),
          span: (chunks) => <span className='filter-name'>{chunks}</span>,
        }}
      />
    );
    action = showAction;
  } else if (sensitive) {
    warning = (
      <FormattedMessage
        id='status.sensitive_warning'
        defaultMessage='Sensitive content'
      />
    );
    action = showAction;
  } else {
    warning = (
      <FormattedMessage
        id='status.media_hidden'
        defaultMessage='Media hidden'
      />
    );
    action = showAction;
  }

  return (
    <div
      className={classNames('spoiler-button', {
        'spoiler-button--hidden': hidden,
        'spoiler-button--click-thru': uncached,
      })}
    >
      <button
        type='button'
        className='spoiler-button__overlay'
        onClick={onClick}
        disabled={uncached}
      >
        <span className='spoiler-button__overlay__label'>
          <span className='spoiler-button__overlay__text'>{warning}</span>
          <span className='spoiler-button__overlay__action'>{action}</span>
        </span>
      </button>
    </div>
  );
};
