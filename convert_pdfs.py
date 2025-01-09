# script.py
import os
import argparse
from pathlib import Path
import multiprocessing
import subprocess
import sys

def run_command(cmd, desc=None):
    """Run command with real-time output"""
    if desc:
        print(f"\n=== {desc} ===")
    
    process = subprocess.Popen(
        cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        bufsize=1
    )
    
    # Print output in real-time
    for line in process.stdout:
        print(line, end='', flush=True)
    
    process.wait()
    if process.returncode != 0:
        raise subprocess.CalledProcessError(process.returncode, cmd)

def setup_marker():
    """Install marker and its dependencies"""
    print("\n=== Setting up marker ===")
    run_command("source ~/.bashrc && conda activate base && pip install marker-pdf", "Installing marker-pdf")
    print("=== Setup complete ===\n")

def get_unconverted_pdfs():
    """Get list of PDFs that haven't been converted yet"""
    input_pdfs = set(f.stem for f in Path("input_pdfs").glob("*.pdf"))
    
    # Check for directories that contain at least one markdown file
    converted = set()
    for dir_path in Path("output_markdown").glob("*"):
        if dir_path.is_dir() and list(dir_path.glob("*.md")):
            converted.add(dir_path.name)
            print(f"Skipping {dir_path.name}.pdf (already converted)")
    
    unconverted = list(input_pdfs - converted)
    if unconverted:
        print(f"\nFound {len(unconverted)} PDFs to convert:")
        for pdf in sorted(unconverted):
            print(f"- {pdf}.pdf")
    
    return unconverted

def process_pdfs(input_bucket, output_bucket, num_workers):
    """Process PDFs from GCS bucket and save results back"""
    print("\n=== Starting PDF processing ===")
    
    # Create local directories
    os.makedirs("input_pdfs", exist_ok=True)
    os.makedirs("output_markdown", exist_ok=True)
    
    # Download PDFs from input bucket
    run_command(
        f"gcloud storage cp -n {input_bucket}/*.pdf input_pdfs/",
        "Downloading PDFs from Cloud Storage (skipping existing files)"
    )
    
    # Get list of PDFs that haven't been converted
    unconverted = get_unconverted_pdfs()
    if not unconverted:
        print("\nAll PDFs have already been converted!")
        return
    
    # Create temporary directory with symlinks to unconverted PDFs
    os.makedirs("to_convert", exist_ok=True)
    for pdf in unconverted:
        os.symlink(f"../input_pdfs/{pdf}.pdf", f"to_convert/{pdf}.pdf")
    
    # Run marker with real-time output
    run_command(
        f"source ~/.bashrc && conda activate base && marker to_convert --workers {num_workers} "
        f"--output_format markdown --output_dir output_markdown",
        "Converting PDFs to Markdown"
    )
    
    # Clean up temporary directory
    for pdf in unconverted:
        try:
            os.unlink(f"to_convert/{pdf}.pdf")
        except OSError:
            pass  # Ignore errors during cleanup
    try:
        os.rmdir("to_convert")
    except OSError:
        pass  # Ignore if directory isn't empty
    
    # Upload results to output bucket
    run_command(
        f"gcloud storage cp -r output_markdown/* {output_bucket}/",
        "Uploading results to Cloud Storage"
    )

def cleanup_old_dirs():
    """Clean up any leftover directories from previous runs"""
    print("\n=== Cleaning up old directories ===")
    try:
        if os.path.exists("to_convert"):
            for f in Path("to_convert").glob("*.pdf"):
                try:
                    os.unlink(f)
                except OSError:
                    pass
            os.rmdir("to_convert")
            print("Cleaned up to_convert directory")
    except Exception as e:
        print(f"Warning: Cleanup failed: {str(e)}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-bucket", required=True, help="GCS input bucket path (gs://...)")
    parser.add_argument("--output-bucket", required=True, help="GCS output bucket path (gs://...)")
    args = parser.parse_args()
    
    print("\n=== Starting conversion script ===")
    
    # Calculate optimal workers based on machine size
    total_ram = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES') / (1024**3)  # GB
    num_cpus = multiprocessing.cpu_count()
    max_workers = min(num_cpus, int(total_ram / 7))  # Marker needs ~7GB per worker
    num_workers = max(1, max_workers)
    
    print(f"\nSystem resources:")
    print(f"- Total RAM: {total_ram:.1f}GB")
    print(f"- CPU cores: {num_cpus}")
    print(f"- Using {num_workers} workers")
    
    try:
        cleanup_old_dirs()
        setup_marker()
        process_pdfs(args.input_bucket, args.output_bucket, num_workers)
        print("\nConversion completed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"\nError: Command failed with exit code {e.returncode}")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()