import os
import firebase_admin
from firebase_admin import auth
from firebase_admin import credentials
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

def initialize_firebase():
    if not firebase_admin._apps:
        logger.info("Initializing Firebase Admin SDK")
        cred = credentials.Certificate('./aspertusia-com-firebase-adminsdk-35ey4-bccc899aea.json')
        # cred = credentials.Certificate({
        #     "type": "service_account",
        #     "project_id": os.getenv('FIREBASE_PROJECT_ID'),
        #     "private_key_id": os.getenv('FIREBASE_PRIVATE_KEY_ID'),
        #     "private_key": os.getenv('FIREBASE_PRIVATE_KEY').replace('\\n', '\n'),
        #     "client_email": os.getenv('FIREBASE_CLIENT_EMAIL'),
        #     "client_id": os.getenv('FIREBASE_CLIENT_ID'),
        #     "auth_uri": os.getenv('FIREBASE_AUTH_URI'),
        #     "token_uri": os.getenv('FIREBASE_TOKEN_URI'),
        #     "auth_provider_x509_cert_url": os.getenv('FIREBASE_AUTH_PROVIDER_X509_CERT_URL'),
        #     "client_x509_cert_url": os.getenv('FIREBASE_CLIENT_X509_CERT_URL')
        # })
        firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK initialized")

def handler(event, context):
    try:
        logger.error("Received event: %s", event)
        initialize_firebase()
        token = event['authorizationToken'].split(' ')[1]  # Split and take the token part after 'Bearer'
        decoded_token = auth.verify_id_token(token, check_revoked=True)
        return generate_policy('user', 'Allow', event['methodArn'])
    except Exception as e:
        logger.error("Error verifying token: %s", e)
        return generate_policy('user', 'Deny', event['methodArn'], str(e))
    
def generate_policy(principal_id, effect, resource, context=""):
    logstr = (f"principal_id: {principal_id}, effect: {effect}, resource: {resource}")
    logger.error(logstr)
    auth_response = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [{
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': resource
            }]
        },
        'context': {
            'reason': context
        }
    }
    return auth_response

