# local_download.py
import os
from pdf_downloader import clean_url, download_pdf

if __name__ == "__main__":
    pdf_url = "https://docs.aws.amazon.com/pdfs/wellarchitected/latest/framework/wellarchitected-framework.pdf?did=wp_card&trk=wp_card"  # Replace with your PDF URL
    save_path = "your.pdf"  # Replace with your desired save path

    cleaned_url = clean_url(pdf_url)

    pdf_data = download_pdf(cleaned_url)
    if pdf_data:
        with open(save_path, 'wb') as f:
            f.write(pdf_data.read())
        print(f"PDF saved locally: {save_path}")
    else:
        print(f"Failed to download or save the PDF: {pdf_url}")
