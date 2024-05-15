import os
import firebase_admin
from firebase_admin import auth
from firebase_admin import credentials
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# Initialize Firebase Admin SDK once
if not firebase_admin._apps:
    logger.info("Initializing Firebase Admin SDK")
    cred = credentials.Certificate('./aspertusia-com-firebase-adminsdk-35ey4-bccc899aea.json')
    firebase_admin.initialize_app(cred)
    logger.info("Firebase Admin SDK initialized")

def handler(event, context):
    try:
        token = event['authorizationToken'].split(' ')[1]  # Split and take the token part after 'Bearer'
        decoded_token = auth.verify_id_token(token, check_revoked=True)
        return generate_policy('user', 'Allow', event['methodArn'])
    except Exception as e:
        logger.error("Error verifying token: %s", e)
        return generate_policy('user', 'Deny', event['methodArn'], str(e))

def generate_policy(principal_id, effect, resource, context=""):
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
