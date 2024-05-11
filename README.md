# chat-app

## Overview
This project is designed as a comprehensive solution incorporating a web frontend, backend services, mobile and desktop applications, all interacting through APIs. It includes serverless backend components using AWS Lambda and API Gateway, with infrastructure managed through AWS CloudFormation and CLI scripts.

``` bash
git clone https://github.com/chanino/chat-app
cd chat-app
```

Run the web content in Docker
``` bash
cd web
docker build -t my-nginx-app:latest .

docker run -p 80:80 --rm \
-e FIREBASE_API_KEY=AIzaSyBc00gsHOuxl-mgv9Mulqcm2j9KI9NP7YQ \
-e FIREBASE_AUTH_DOMAIN=aspertusia-com.firebaseapp.com \
-e FIREBASE_PROJECT_ID=aspertusia-com \
-e FIREBASE_STORAGE_BUCKET=379958625282 \
-e FIREBASE_MESSAGING_SENDER_ID=379958625282 \
-e FIREBASE_APP_ID=1:379958625282:web:fd9a5a60d11be8c18a931b \
-e FIREBASE_MEASUREMENT_ID=G-168JPDD8GL \
my-nginx-app:latest
````

```
