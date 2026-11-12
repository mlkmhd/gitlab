/* eslint-disable import-x/no-commonjs */
const yaml = require('yaml');

// This will transform YAML files to JSON strings
module.exports = {
  process: (sourceContent) => {
    const jsonContent = yaml.parse(sourceContent);
    const json = JSON.stringify(jsonContent);
    return { code: `module.exports = ${json}` };
  },
};
