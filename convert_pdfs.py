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
    run_command("pip install marker-pdf", "Installing marker-pdf")

def process_pdfs(input_bucket, output_bucket, num_workers):
    """Process PDFs from GCS bucket and save results back"""
    # Create local directories
    os.makedirs("input_pdfs", exist_ok=True)
    os.makedirs("output_markdown", exist_ok=True)
    
    # Download PDFs from input bucket
    run_command(
        f"gcloud storage cp -n {input_bucket}/*.pdf input_pdfs/",
        "Downloading PDFs from Cloud Storage (skipping existing files)"
    )
    
    # Run marker with real-time output
    run_command(
        f"marker input_pdfs --workers {num_workers} "
        f"--output_format markdown --output_dir output_markdown "
        f"--skip_existing",
        "Converting PDFs to Markdown"
    )
    
    # Upload results to output bucket
    run_command(
        f"gcloud storage cp -r output_markdown/* {output_bucket}/",
        "Uploading results to Cloud Storage"
    )

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-bucket", required=True, help="GCS input bucket path (gs://...)")
    parser.add_argument("--output-bucket", required=True, help="GCS output bucket path (gs://...)")
    args = parser.parse_args()
    
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