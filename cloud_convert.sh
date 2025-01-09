#!/bin/bash
set -e  # Exit on error

# Default values
INSTANCE_NAME="marker-instance"
ZONE="europe-west3-b"
MACHINE_TYPE="e2-highmem-8"
INPUT_BUCKET="pdf-to-md-input"
OUTPUT_BUCKET="pdf-to-md-output"

# Help message
show_help() {
    echo "Usage: $0 [options] <pdf_directory>"
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -z, --zone ZONE          GCP zone (default: europe-west3-b)"
    echo "  -m, --machine MACHINE    Machine type (default: e2-highmem-8)"
    echo "  -i, --instance NAME      Instance name (default: marker-instance)"
    echo "  --input-bucket NAME      Input bucket name (default: pdf-to-md-input)"
    echo "  --output-bucket NAME     Output bucket name (default: pdf-to-md-output)"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -m|--machine)
            MACHINE_TYPE="$2"
            shift 2
            ;;
        -i|--instance)
            INSTANCE_NAME="$2"
            shift 2
            ;;
        --input-bucket)
            INPUT_BUCKET="$2"
            shift 2
            ;;
        --output-bucket)
            OUTPUT_BUCKET="$2"
            shift 2
            ;;
        *)
            PDF_DIR="$1"
            shift
            ;;
    esac
done

# Check for required arguments
if [ -z "$PDF_DIR" ]; then
    echo "Error: PDF directory is required"
    show_help
    exit 1
fi

# Ensure PDF directory exists
if [ ! -d "$PDF_DIR" ]; then
    echo "Error: Directory $PDF_DIR does not exist"
    exit 1
fi

echo "Setting up Google Cloud resources..."

# Create buckets if they don't exist
echo "Creating storage buckets..."
gcloud storage buckets create gs://$INPUT_BUCKET 2>/dev/null || true
gcloud storage buckets create gs://$OUTPUT_BUCKET 2>/dev/null || true

# Upload PDFs
echo "Uploading PDFs from $PDF_DIR..."
gcloud storage cp "$PDF_DIR"/*.pdf gs://$INPUT_BUCKET/

# Create instance
echo "Creating Compute Engine instance..."
gcloud compute instances create $INSTANCE_NAME \
    --machine-type=$MACHINE_TYPE \
    --image-family=pytorch-latest-cpu \
    --image-project=deeplearning-platform-release \
    --boot-disk-size=100GB \
    --boot-disk-type=pd-balanced \
    --scopes=storage-full \
    --zone=$ZONE

# Copy conversion script
echo "Copying conversion script..."
gcloud compute scp convert_pdfs.py $INSTANCE_NAME:~/ --zone=$ZONE

# Create cleanup script on instance
echo "Setting up cleanup script..."
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="cat > cleanup.sh << 'EOF'
#!/bin/bash
# Upload logs
gcloud storage cp conversion.log gs://$OUTPUT_BUCKET/logs/
# Delete input bucket
gcloud storage rm -r gs://$INPUT_BUCKET
# Delete the instance itself
gcloud compute instances delete $INSTANCE_NAME --zone=$ZONE --quiet
EOF
chmod +x cleanup.sh"

# Start conversion
echo "Starting PDF conversion..."
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="nohup bash -c '
python3 convert_pdfs.py \
    --input-bucket gs://$INPUT_BUCKET \
    --output-bucket gs://$OUTPUT_BUCKET \
    > conversion.log 2>&1
RETVAL=\$?
./cleanup.sh
exit \$RETVAL' &"

echo "Conversion started! You can monitor progress with:"
echo "gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='tail -f conversion.log'"
echo
echo "When finished, results will be in gs://$OUTPUT_BUCKET/"
echo "Download them with:"
echo "gcloud storage cp -r gs://$OUTPUT_BUCKET/* ./markdown_output/"
``` 