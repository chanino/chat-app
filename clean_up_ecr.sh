#!/bin/bash

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

# List all images in the repository
IMAGES=$(aws ecr describe-images --repository-name $REPO_NAME \
    --region $REGION --profile $PROFILE \
    --query 'imageDetails[*].[imageDigest,imageTags]' --output json)

# Parse the JSON output to find images to delete
IMAGES_TO_DELETE=()
for row in $(echo "${IMAGES}" | jq -r '.[] | @base64'); do
    _jq() {
        echo ${row} | base64 --decode | jq -r ${1}
    }

    IMAGE_DIGEST=$(_jq '.[0]')
    IMAGE_TAGS=$(_jq '.[1]')

    # Skip images with important tags (e.g., "latest")
    if [[ "$IMAGE_TAGS" == *"latest"* || "$IMAGE_TAGS" == *"chat-bro-batch-job"* ]]; then
        continue
    fi

    # Add image digest to the list of images to delete
    IMAGES_TO_DELETE+=("$IMAGE_DIGEST")
done

# Delete images
if [ ${#IMAGES_TO_DELETE[@]} -eq 0 ]; then
    echo "No images to delete."
else
    for IMAGE_DIGEST in "${IMAGES_TO_DELETE[@]}"; do
        echo "Deleting image: $IMAGE_DIGEST"
        aws ecr batch-delete-image --repository-name $REPO_NAME --image-ids imageDigest=$IMAGE_DIGEST \
        --region $REGION --profile $PROFILE
    done
fi
