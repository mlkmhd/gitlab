import {
  classifyGlqlError,
  GLQL_ERROR_GENERIC,
  GLQL_ERROR_INVALID_QUERY,
  GLQL_ERROR_NO_ACCESS,
  GLQL_ERROR_NOT_CONFIGURED,
  GLQL_ERROR_QUERY_PAUSED,
  GLQL_ERROR_RATE_LIMITED,
  GLQL_ERROR_TIMEOUT,
  GLQL_ERROR_UNAVAILABLE,
  retryAfterSeconds,
} from '~/glql/utils/error_classifier';

describe('classifyGlqlError', () => {
  const withCode = (code) => ({ graphQLErrors: [{ message: 'failed', extensions: { code } }] });

  it.each`
    description                             | error                                      | category
    ${'no error'}                           | ${undefined}                               | ${GLQL_ERROR_GENERIC}
    ${'a plain Error (parse/transform)'}    | ${new Error('boom')}                       | ${GLQL_ERROR_INVALID_QUERY}
    ${'a TypeError from our own code'}      | ${new TypeError('boom')}                   | ${GLQL_ERROR_GENERIC}
    ${'an unknown extension code'}          | ${withCode('SOMETHING_ELSE')}              | ${GLQL_ERROR_GENERIC}
    ${'the aggregation authorization code'} | ${withCode('AGGREGATION_NOT_AUTHORIZED')}  | ${GLQL_ERROR_NO_ACCESS}
    ${'the Siphon unavailable code'}        | ${withCode('SIPHON_REPLICATION_DISABLED')} | ${GLQL_ERROR_UNAVAILABLE}
    ${'the ClickHouse configuration code'}  | ${withCode('CLICKHOUSE_NOT_CONFIGURED')}   | ${GLQL_ERROR_NOT_CONFIGURED}
    ${'an HTTP 503 (query timeout)'}        | ${{ networkError: { statusCode: 503 } }}   | ${GLQL_ERROR_TIMEOUT}
    ${'an HTTP 429 (rate limited)'}         | ${{ networkError: { statusCode: 429 } }}   | ${GLQL_ERROR_RATE_LIMITED}
    ${'an HTTP 500'}                        | ${{ networkError: { statusCode: 500 } }}   | ${GLQL_ERROR_GENERIC}
  `('classifies $description as $category', ({ error, category }) => {
    expect(classifyGlqlError(error)).toBe(category);
  });

  // `/api/glql` uses 403 for both rate limiting and real authorization failures;
  // only the response body tells them apart.
  describe('HTTP 403', () => {
    const forbidden = (message) => ({
      networkError: { statusCode: 403, result: { errors: [{ message }] } },
    });

    it('classifies the repeated-timeout lock as a paused query', () => {
      expect(
        classifyGlqlError(
          forbidden(
            'Query temporarily blocked due to repeated timeouts. Please try again later or narrow your search scope.',
          ),
        ),
      ).toBe(GLQL_ERROR_QUERY_PAUSED);
    });

    it.each([
      ['an authorization 403', forbidden('API not accessible for user.')],
      ['a 403 with no parsed body', { networkError: { statusCode: 403 } }],
    ])('classifies %s as no access', (_, error) => {
      expect(classifyGlqlError(error)).toBe(GLQL_ERROR_NO_ACCESS);
    });
  });

  // Backends predating the extension codes emit only the message.
  it.each([
    "ordering by 'credits_used.sum' is not authorized",
    "access to metric 'credits_used.sum' is not authorized",
    "access to dimension 'foo' is not authorized",
  ])('classifies the legacy message %p as no access', (message) => {
    expect(classifyGlqlError({ message })).toBe(GLQL_ERROR_NO_ACCESS);
    expect(classifyGlqlError({ graphQLErrors: [{ message }] })).toBe(GLQL_ERROR_NO_ACCESS);
  });

  it('classifies from the first recognizable error in a list', () => {
    const error = {
      graphQLErrors: [
        { message: 'something else' },
        { message: 'failed', extensions: { code: 'SIPHON_REPLICATION_DISABLED' } },
      ],
    };

    expect(classifyGlqlError(error)).toBe(GLQL_ERROR_UNAVAILABLE);
  });
});

describe('retryAfterSeconds', () => {
  const withRetryAfter = (value) => ({
    networkError: {
      statusCode: 429,
      response: { headers: { get: (name) => (name === 'Retry-After' ? value : null) } },
    },
  });

  it.each`
    description                | value                              | seconds
    ${'a short delay'}         | ${'5'}                             | ${5}
    ${'a long delay'}          | ${'900'}                           | ${900}
    ${'zero'}                  | ${'0'}                             | ${0}
    ${'no header'}             | ${null}                            | ${null}
    ${'an HTTP date'}          | ${'Wed, 21 Oct 2026 07:28:00 GMT'} | ${null}
    ${'a negative number'}     | ${'-1'}                            | ${null}
    ${'a fractional number'}   | ${'1.5'}                           | ${null}
    ${'an empty header value'} | ${''}                              | ${null}
  `('reads $description as $seconds', ({ value, seconds }) => {
    expect(retryAfterSeconds(withRetryAfter(value))).toBe(seconds);
  });

  it.each`
    description             | error
    ${'no error'}           | ${undefined}
    ${'no network error'}   | ${new Error('boom')}
    ${'no response object'} | ${{ networkError: { statusCode: 429 } }}
  `('returns null for $description', ({ error }) => {
    expect(retryAfterSeconds(error)).toBe(null);
  });
});
