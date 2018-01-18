import sys
import time
import urllib
import hmac
import hashlib
import base64

uri = sys.argv[1]
sas_name = sys.argv[2]
sas = sys.argv[3].encode('utf-8')

expiry = str(int(time.time() + (60 * 60 * 24)))
string_to_sign = (uri + '\n' + expiry).encode('utf-8')
signed_hmac_sha256 = hmac.HMAC(sas, string_to_sign, hashlib.sha256)
signature = urllib.pathname2url(base64.b64encode(signed_hmac_sha256.digest()))
sas_token = 'SharedAccessSignature sr={}&sig={}&se={}&skn={}'.format(uri, signature, expiry, sas_name)

print sas_token