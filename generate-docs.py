import os
import sys

def extractAllDocumentation(file: str):
    doc_lines = []

    try:
        with open(file, "r") as f:
            lines = f.readlines()

            for line in lines:
                if line.startswith("///") and line.strip() != "///":
                    doc_lines.append(line.strip())
    except OSError as error:
        print(f"error: failed to extract documentation because of error: {error}")
        sys.exit(1)
    
    return doc_lines

for dir_path, dir_names, files in os.walk("."):
    for file in files:
        if file.endswith(".zig"):

           sub_path = os.path.join(dir_path, file)
           docs = extractAllDocumentation(sub_path)

           print(f"documentation in {sub_path}")

           for doc_line in docs:
               print(f"  {doc_line}")
