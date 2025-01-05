#!/bin/bash

# Error codes
readonly ERR_RATE_LIMIT=10
readonly ERR_DOWNLOAD=11
readonly ERR_CONVERSION=12
readonly ERR_CONFIG=13

# Default output directory is ./scrape
output_dir="./scrape"

# Load API key from .env file
if [ ! -f ".env" ]; then
    echo "Error: .env file not found" >&2
    exit $ERR_CONFIG
fi

# Source the .env file
set -a
source .env
set +a

# Check if API key is set
if [ -z "$HTML2MD_API_KEY" ]; then
    echo "Error: HTML2MD_API_KEY not found in .env file" >&2
    exit $ERR_CONFIG
fi

# Function to print usage
print_usage() {
    echo "Usage: $0 <url_or_file> [output_directory]"
    echo "  url_or_file: Either a URL to convert or a file containing URLs"
    echo "  output_directory: (optional) Directory to save the markdown files"
    exit 1
}

# Function to sanitize title for filename
sanitize_title() {
    local title="$1"
    echo "$title" | \
        sed 's/\[.*\]//g' | \
        sed 's/([^)]*)//g' | \
        sed 's/[\/\\*"<>|]//g' | \
        sed 's/  */ /g' | \
        sed 's/^ *//;s/ *$//'
}

# Function to convert HTML to markdown using API
convert_html_to_md() {
    local url="$1"
    local output_dir="$2"
    local tmp_html=$(mktemp)
    local tmp_json=$(mktemp)

    # Download HTML to temp file
    curl -s "$url" > "$tmp_html"

    # Create JSON payload
    jq -n --rawfile html "$tmp_html" --arg domain "$url" \
        '{html: $html, domain: $domain}' > "$tmp_json"

    # Send to API
    local response=$(curl -s \
        -H "X-API-Key: $HTML2MD_API_KEY" \
        -H "Content-Type: application/json" \
        -d "@$tmp_json" \
        -X POST \
        https://api.html-to-markdown.com/v1/convert)

    # Check for rate limiting
    if echo "$response" | grep -q "TOO_MANY_REQUESTS"; then
        rm -f "$tmp_html" "$tmp_json"
        return $ERR_RATE_LIMIT
    fi

    # Extract markdown content
    local markdown=$(echo "$response" | jq -r '.markdown')

    # Clean up temp files
    rm -f "$tmp_html" "$tmp_json"

    if [ -z "$markdown" ] || [ "$markdown" = "null" ]; then
        return $ERR_CONVERSION
    fi

    # Strip content before first heading
    if echo "$markdown" | grep -q "^# "; then
        markdown=$(echo "$markdown" | sed -n '/^# /,$p')
    fi

    # Extract title from first heading
    local title=$(echo "$markdown" | grep -m 1 "^# " | sed 's/^# //')
    if [ -z "$title" ]; then
        title=$(echo "$url" | sed 's/https\?:\/\///' | sed 's/[\/.]/-/g')
    fi

    # Sanitize title
    local sanitized_title=$(sanitize_title "$title")
    if [ -z "$sanitized_title" ]; then
        sanitized_title="converted-$(date +%Y%m%d-%H%M%S)"
    fi

    # Save to file
    local filepath="${output_dir}/${sanitized_title}.md"
    mkdir -p "$(dirname "$filepath")"
    printf '%s\n' "$markdown" > "$filepath"
    echo "$url -> $filepath"
    return 0
}

# Function to convert PDF using marker_single
convert_pdf_to_md() {
    local pdf_path="$1"
    local output_dir="$2"
    local fallback_title="$3"
    local temp_dir=$(mktemp -d)
    
    # Convert using marker_single
    marker_single --output_dir "$temp_dir" "$pdf_path"
    
    # Get the conversion output directory
    local filename=$(basename "$pdf_path")
    local conv_dir="$temp_dir/${filename%.*}"
    
    if [ -d "$conv_dir" ]; then
        # Find the markdown file
        local md_file=$(find "$conv_dir" -name "*.md" -type f)
        if [ -n "$md_file" ]; then
            # Extract title from first heading
            local title=$(head -n 1 "$md_file" | sed 's/^# //')
            local sanitized_title=$(sanitize_title "$title")
            
            # If sanitized title is empty, use fallback
            if [ -z "$sanitized_title" ]; then
                sanitized_title="$fallback_title"
            fi
            
            # Move and rename the markdown file
            mv "$md_file" "$output_dir/${sanitized_title}.md"
            echo "$pdf_path -> $output_dir/${sanitized_title}.md"
            rm -rf "$temp_dir"
            return 0
        fi
    fi
    
    rm -rf "$temp_dir"
    return $ERR_CONVERSION
}

# Function to process a single URL
process_url() {
    local url="$1"
    local output_dir="$2"
    local current_section="$3"

    # Update output directory if section is provided
    if [ ! -z "$current_section" ]; then
        section_path="${current_section#Resources/}"
        section_dir="${section_path%.md}"
        output_dir="$output_dir/${section_dir}"
    fi
    mkdir -p "$output_dir"

    # Handle arXiv URLs
    if [[ "$url" =~ arxiv\.org/(abs|pdf)/([0-9]+\.[0-9]+) ]]; then
        local arxiv_id="${BASH_REMATCH[2]}"
        local html_url="https://ar5iv.org/html/$arxiv_id"
        
        # Try HTML version first
        convert_html_to_md "$html_url" "$output_dir"
        local result=$?
        
        if [ $result -ne 0 ]; then
            # Fall back to PDF
            echo "HTML conversion failed, trying PDF instead" >&2
            local pdf_url="https://arxiv.org/pdf/${arxiv_id}.pdf"
            local temp_pdf=$(mktemp)
            curl -L -s "$pdf_url" -o "$temp_pdf"
            convert_pdf_to_md "$temp_pdf" "$output_dir" "$arxiv_id"
            result=$?
            rm -f "$temp_pdf"
        fi
        return $result
    
    # Handle PDF URLs
    elif [[ "$url" =~ \.pdf$ ]]; then
        local filename=$(basename "$url")
        local temp_pdf=$(mktemp)
        curl -L -s "$url" -o "$temp_pdf"
        convert_pdf_to_md "$temp_pdf" "$output_dir" "${filename%.*}"
        local result=$?
        rm -f "$temp_pdf"
        return $result
    
    # Handle HTML URLs
    else
        convert_html_to_md "$url" "$output_dir"
        return $?
    fi
}

# Function to process a file containing URLs
process_file() {
    local input_file="$1"
    local output_dir="$2"
    local current_section=""
    local processed_urls=()
    local is_markdown=false
    
    # Check if file contains markdown formatting by looking for markdown links or headers
    if grep -q -E '^\s*-.*\[.*\]\(.*\)' "$input_file" || grep -q '^#' "$input_file"; then
        is_markdown=true
    fi
    
    while read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        if [ "$is_markdown" = true ]; then
            # Handle markdown formatted file
            
            # Check for section headers
            if [[ "$line" =~ ^##[[:space:]]+(.*\.md)$ ]]; then
                current_section="${BASH_REMATCH[1]}"
                current_section=$(echo "$current_section" | sed 's/[\/\\*"<>|]//g')
                continue
            fi
            
            # Skip lines that don't start with a dash
            [[ "$line" =~ ^- ]] || continue
            
            # Extract URL from markdown link
            url=$(echo "$line" | sed -n 's/.*(\([^)]*\)).*/\1/p')
        else
            # Handle plain URL list - each line is a URL
            url=$(echo "$line" | tr -d '[:space:]')
        fi
        
        # Skip if not a URL or already processed
        [[ -z "$url" ]] && continue
        [[ " ${processed_urls[@]} " =~ " ${url} " ]] && continue
        
        # Process URL
        if [[ "$url" =~ ^https?:// ]]; then
            processed_urls+=("$url")
            process_url "$url" "$output_dir" "$current_section"
        fi
    done < "$input_file"
}

# Main script

# Check if input is provided
if [ $# -lt 1 ]; then
    print_usage
fi

input="$1"
if [ ! -z "$2" ]; then
    output_dir="$2"
fi

# Create output directory
mkdir -p "$output_dir"

# Check if input is a file or URL
if [ -f "$input" ]; then
    process_file "$input" "$output_dir"
elif [[ "$input" =~ ^https?:// ]]; then
    process_url "$input" "$output_dir"
else
    echo "Error: Input must be either a valid URL or an existing file" >&2
    print_usage
fi