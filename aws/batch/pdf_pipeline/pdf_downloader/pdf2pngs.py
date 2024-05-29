from io import BytesIO
from pdf2image import convert_from_bytes
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def convert_pdf2pngs(pdf_content):
    """
    Converts PDF content to a list of PNG images.
    
    Args:
    - pdf_content (bytes): The content of the PDF file.
    
    Returns:
    - List of BytesIO objects, each containing the PNG data for a single page.
    """
    images = convert_from_bytes(pdf_content)
    logger.info(f"Number of pages: {len(images)}")
    png_images = []
    
    for i, image in enumerate(images, start=1):
        image_buffer = BytesIO()
        image.save(image_buffer, format='PNG')
        image_buffer.seek(0)
        png_images.append(image_buffer)
        logger.info(f"Converted page {i} to PNG")
    
    return png_images
