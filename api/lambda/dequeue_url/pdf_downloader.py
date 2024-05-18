# pdf_downloader.py
import re
import requests
import logging
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry
from io import BytesIO
from urllib.parse import urlparse, urlunparse

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Setup requests session with retries
session = requests.Session()
retry = Retry(
    total=5,
    backoff_factor=0.3,
    status_forcelist=(500, 502, 504),
)
adapter = HTTPAdapter(max_retries=retry)
session.mount('http://', adapter)
session.mount('https://', adapter)

def is_valid_pdf(content):
    return content.startswith(b'%PDF')

def clean_url(pdf_url):
    parsed_url = urlparse(pdf_url)
    cleaned_url = urlunparse(parsed_url._replace(query='', fragment=''))
    return cleaned_url

def download_pdf(cleaned_url):
    try:
        if not re.match(r'^https?://.*\.pdf$', cleaned_url, re.IGNORECASE):
            logger.info(f"Not a PDF URL: {cleaned_url}")
            return None
        
        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'}
        response = session.get(cleaned_url, headers=headers, stream=True)
        response.raise_for_status()

        pdf_data = BytesIO()
        for chunk in response.iter_content(chunk_size=1024):
            pdf_data.write(chunk)
        pdf_data.seek(0)

        if not is_valid_pdf(pdf_data.read(4)):
            logger.error(f"Downloaded content is not a valid PDF: {cleaned_url}")
            return None

        pdf_data.seek(0)
        return pdf_data

    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to download PDF: {cleaned_url}, error: {e}")
        return None
    except ValueError as e:
        logger.error(f"Invalid PDF content from URL: {cleaned_url}, error: {e}")
        return None
