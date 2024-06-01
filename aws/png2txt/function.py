from openai import OpenAI
import base64
from dotenv import load_dotenv
import time
import random

load_dotenv()
client = OpenAI()

##########################

def png2txt(base64_image, max_retries=5):
    instruction = ("This image was created from a single page of a PDF document. "
                   "Extract the text from this image into a markdown format that "
                   "mimics the structure of the original PDF page in the image. "
                   "Provide the extracted text, but no other information. "
                   "For example, do not start with a lead-in like 'This image contains'.")
    retries = 0
    while retries < max_retries:
        try:
            response = client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                "role": "user",
                "content": [
                    {"type": "text", "text": instruction},
                    {
                    "type": "image_url",
                    "image_url": {
                        "url":f"data:image/png;base64,{base64_image}", 
                        "detail": "low"
                    },
                    },
                ],
                }
            ],
            max_tokens=300,
            )

            return response.choices[0].message.content
        except Exception as e:
            retries += 1
            if retries >= max_retries:
                raise e
            wait_time = (2 ** retries) + random.uniform(0, 1)
            print(f"Retry {retries}/{max_retries} after error: {e}. Waiting for {wait_time:.2f} seconds.")
            time.sleep(wait_time)

#############################
def encode_image(image_path):
  with open(image_path, "rb") as image_file:
    return base64.b64encode(image_file.read()).decode('utf-8')


#########################
image_path = "page-2.png"
base64_image = encode_image(image_path)
txt = png2txt(base64_image)
print(txt)
