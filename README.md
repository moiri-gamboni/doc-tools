# Document Conversion Tools

A collection of tools to help with document and web content management. These tools allow you to:
- Extract and validate links from markdown files
- Convert web pages and PDFs to markdown format
- Process multiple URLs in batch
- Special handling for academic papers (arXiv)

## Setup

1. Install [marker](https://github.com/VikParuchuri/marker) for PDF processing:
```bash
pip install marker-pdf
```

2. Install [pandoc](https://pandoc.org/installing.html) for markdown link extraction:
```bash
# Ubuntu/Debian
sudo apt-get install pandoc

# macOS
brew install pandoc

# Windows (using chocolatey)
choco install pandoc
```

3. Set up HTML to Markdown API:
   - Go to [html-to-markdown.com/api](https://html-to-markdown.com/api)
   - Sign up and get your API key
   - Create a `.env` file in the project root:
```bash
HTML2MD_API_KEY=your_api_key_here
```

## Available Scripts

### find_md_links.sh

This script finds and reports all markdown links in your markdown files.

Usage:
```bash
./find_md_links.sh [directory] [-c|--check]
```

- `directory`: Optional. Directory to search (default: current directory)
- `-c` or `--check`: Optional. Check if links are valid

The script generates a `markdown_links.md` report containing all found links.

### html2md.sh

This script converts web pages and PDFs to markdown format.

Usage:
```bash
./html2md.sh <url_or_file> [output_directory]
```

- `url_or_file`: Either a URL to convert or a file containing URLs
- `output_directory`: Optional. Directory to save the markdown files (default: ./Scrape)

Features:
- Converts HTML pages to markdown
- Handles PDF files using marker
- Special handling for arXiv papers
- Supports batch processing from a file containing URLs

### convert_pdfs.py

This script uses Google Cloud Compute Engine to convert large batches of PDFs to markdown format using marker. It's particularly useful when you have many PDFs to process, as it uses cloud resources instead of your local machine.

Prerequisites:
1. Install Google Cloud CLI following the [official installation guide](https://cloud.google.com/sdk/docs/install-sdk)

2. Initialize Google Cloud and set up a project:
```bash
gcloud init
```

Usage:
```bash
# Run with default settings
./cloud_convert.sh path/to/pdf/directory

# Or customize settings
./cloud_convert.sh --zone us-central1-a --machine e2-highmem-16 path/to/pdf/directory
```

Available options:
- `-h, --help`: Show help message
- `-z, --zone ZONE`: GCP zone (default: europe-west3-b)
- `-m, --machine MACHINE`: Machine type (default: e2-highmem-8)
- `-i, --instance NAME`: Instance name (default: marker-instance)
- `--input-bucket NAME`: Input bucket name (default: pdf-to-md-input)
- `--output-bucket NAME`: Output bucket name (default: pdf-to-md-output)

The script will:
1. Create storage buckets
2. Upload your PDFs
3. Create and configure a Compute Engine instance
4. Start the conversion process
5. Automatically clean up resources when done
6. Save logs to the output bucket

Notes:
- The script uses an e2-highmem-8 instance (8 CPUs, 64GB RAM) which can run 8-9 marker workers in parallel
- Files are processed in batches to avoid memory issues
- Progress can be monitored through the conversion.log file
- The instance will continue running (and charging) until explicitly deleted
- If the script is interrupted, rerunning it will automatically skip already processed files (using marker's --skip_existing flag)
- The script also uses the -n flag with gcloud storage cp to avoid re-downloading already downloaded PDFs
