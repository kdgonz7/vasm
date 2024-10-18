import os
import sys

def extractAllDocumentation(file: str):
    todo_lines = []

    try:
        with open(file, "r") as f:
            lines = f.readlines()

            for line in lines:
                if line.find("TODO") != -1:
                    todo_lines.append(line.strip())

    except OSError as error:
        print(f"error: failed to extract documentation because of error: {error}")
        sys.exit(1)
    
    return todo_lines

for dir_path, dir_names, files in os.walk("."):
    for file in files:
        if file.endswith(".zig"):

           sub_path = os.path.join(dir_path, file)
           todos = extractAllDocumentation(sub_path)

           if len(todos) <= 0: continue

           print(f"documentation in {sub_path}")

           for todo_line in todos:
               print(f"  {todo_line}")
