#!/usr/bin/env python3


import sys
import subprocess
import tempfile
import shutil
import os


def process_input(cmd_str: str, file_suffix: str):
    try:
        # Step 1: Read the entire input from stdin and create a temporary in-memory file
        input_data = sys.stdin.read()
        tmp_file = tempfile.m
        tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix="wrapped" + file_suffix)
        tmp_file.write(input_data.encode())
        print(tmp_file)
        return 
        

        # Step 2: Execute the program with the temporary file as input
        cmd = cmd_str.split(" ") + [tmp_file.name]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        # Step 3: After the program finishes, read the modified content of the tmp file
        with open(tmp_file.name, "r") as modified_file:
            modified_content = modified_file.read()

        # Step 4: Output the modified content to stdout
        print(modified_content)
        print("res ", result)
        print("cmd: ", cmd)

    finally:
        # Step 5: Clean up resources
        os.remove(tmp_file.name)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python file_processor.py <cmd> <file_suffix>")
        sys.exit(1)

    cmd = sys.argv[1]
    file_suffix = sys.argv[2]

    process_input(cmd, file_suffix)
