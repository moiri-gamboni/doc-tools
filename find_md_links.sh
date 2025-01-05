#!/bin/bash

# Parse arguments
search_dir="."
output_file="markdown_links.md"
check_links=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--check) check_links=true ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) search_dir="$1" ;;
    esac
    shift
done

# Check for pandoc
if ! command -v pandoc &> /dev/null; then
    echo "Error: pandoc is required but not installed." >&2
    exit 1
fi

# Initialize output file
echo "# Markdown Links Report" > "$output_file"
echo "" >> "$output_file"

# Process markdown files
find "$search_dir" -type f -name "*.md" | while read -r file; do
    # Skip the output file itself
    rel_path=$(realpath --relative-to="$PWD" "$file")
    [[ "$rel_path" = "$output_file" ]] && continue
    
    # Extract links using pandoc and jq
    links=$(pandoc -f markdown -t json "$file" | \
        jq -r '.. | select(.t? == "Link") | 
            "[\(.c[1] | map(if .t == "Str" then .c 
                          elif .t == "Space" then " "
                          elif .t == "Code" then .c
                          else "" end) | join(""))](\(.c[2][0]))"')
    
    # Add links to report if any found
    if [ ! -z "$links" ]; then
        echo "## $rel_path" >> "$output_file"
        echo "" >> "$output_file"
        
        while read -r link; do
            [ -z "$link" ] && continue
            
            if [ "$check_links" = true ]; then
                url=$(echo "$link" | sed -E 's/.*\(([^)]*)\)/\1/')
                if [[ "$url" =~ ^http ]]; then
                    if curl --output /dev/null --silent --head --fail "$url"; then
                        echo "- ✓ $link" >> "$output_file"
                    else
                        echo "- ❌ $link" >> "$output_file"
                    fi
                else
                    echo "- $link" >> "$output_file"
                fi
            else
                echo "- $link" >> "$output_file"
            fi
        done <<< "$links"
        
        echo "" >> "$output_file"
    fi
done

echo "Link report generated in $output_file"