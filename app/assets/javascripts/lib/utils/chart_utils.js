/**
 * Takes a dataset and returns an array containing the y-values of it's first and last entry.
 * (e.g., [['xValue1', 'yValue1'], ['xValue2', 'yValue2'], ['xValue3', 'yValue3']] will yield ['yValue1', 'yValue3'])
 *
 * @param {Array} data
 * @returns {[*, *]}
 */
export const firstAndLastY = (data) => {
  const [firstEntry] = data;
  const [lastEntry] = data.slice(-1);

  const firstY = firstEntry[1];
  const lastY = lastEntry[1];

  return [firstY, lastY];
};
