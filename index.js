const common = require('azure-iot-common');

const CONNECTION_STRING = common.ConnectionString.parse(process.env.EVENT_HUB_CONNECTION);
const HOST = CONNECTION_STRING.Endpoint.split('sb://')[1].split('/')[0];
const PATH = '/' + CONNECTION_STRING.EntityPath + '/messages';

const EXPIRY = Math.ceil((Date.now() / 1000) + 3600 * 24); // 24 hours from now
const SAS_TOKEN = common.SharedAccessSignature.create(
  common.encodeUriComponentStrict('https://' + HOST + PATH),
  CONNECTION_STRING.SharedAccessKeyName,
  Buffer.from(CONNECTION_STRING.SharedAccessKey).toString('base64'),
  EXPIRY
).toString();

module.exports.printHeader = function () {
  console.log('Authorization: ' + SAS_TOKEN);
};

module.exports.printUrl = function () {
  console.log('https://' + HOST + PATH);
};
