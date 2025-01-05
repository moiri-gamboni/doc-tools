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
