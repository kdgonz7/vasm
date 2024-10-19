from sys import argv
from os import system as internal_system, makedirs, listdir, walk
from os.path import basename, join
from shutil import which
from colorama import Fore, Style
from webbrowser import open as open_url

# The format used to generate web docs
WEB_FORMAT = "html"

# The format used for the manual pages
MAN_FORMAT = "manpage"

# The asciidoctor binary location
ASCIIDOCTOR = which("asciidoctor")

# The zig binary location
ZIG = which("zig")


# Helper functions
def system(command: str) -> None:
    command_fragments = command.split(" ")
    command_fragments[0] = (
        f" {Fore.BLACK}{Style.DIM}{basename(command_fragments[0])}{Style.RESET_ALL}"
    )

    print(
        f"{' '.join(command_fragments)}",
        flush=True,
    )
    internal_system(command)


def ensure_dir(path):
    makedirs(path, exist_ok=True)


# Ensure steps
def ensure_zig():
    if ZIG is None:
        print(
            f"{Fore.YELLOW}{Style.DIM}EnsureZig failed: VASM requires Zig to be installed.{Style.RESET_ALL}{Fore.RESET}"
        )

        exit(1)
    else:
        print(f"has zig.....{Fore.GREEN}yes{Style.RESET_ALL}{Fore.RESET}")


def ensure_asciidoc():
    if ASCIIDOCTOR is None:
        print(
            f"{Fore.YELLOW}{Style.DIM}EnsureAsciiDoc failed: VASM requires Asciidoctor to be installed.{Style.RESET_ALL}{Fore.RESET}"
        )

        exit(1)


def tests():
    """Builds the tests suite"""
    system(f"{ZIG} build tests")


def tests_summary():
    """Builds the tests suite and runs it with the --summary flag"""
    system(f"{ZIG} build tests --summary all")


def clean():
    """Cleans any zig cache files."""
    system("rm zig-out -rf")
    system("rm .zig-cache -rf")


def docs():
    # make sure the man/man1 directories exist
    ensure_dir("man/man1")
    ensure_dir("docs/man/")


def site():
    """Builds the site documentation. Reading every .adoc file in the docs/ directory"""

    for dir_path, dir_names, files in walk("docs"):
        for file in files:
            if file.endswith(".adoc"):
                system(f"{ASCIIDOCTOR} -b {WEB_FORMAT} {join(dir_path, file)}")


def man_pages():
    """Builds the man pages"""

    for file in listdir("man-src"):
        if file.endswith(".adoc"):
            system(
                f"{ASCIIDOCTOR} -b {WEB_FORMAT} ./man-src/{file} -o ./docs/man/{file[0:-5]}.html"
            )
            system(
                f"{ASCIIDOCTOR} -b {MAN_FORMAT} ./man-src/{file} -o ./man/man1/{file[0:-5]}.1"
            )


def vasm():
    """Builds the vasm program"""
    system(f"{ZIG} build --summary all")


def find_bad_lines():
    """locates any std.debug.print() calls in the source code"""
    print("reporting on source code...")
    for dir_path, dir_names, files in walk("src"):
        for file in files:
            if file.endswith(".zig"):
                with open(join(dir_path, file), "r", encoding="utf-8") as f:
                    lines = f.read()

                    for line in lines:
                        if line.find("std.debug.print") != -1:
                            print(f"{join(dir_path, file)}: {line.strip()}")

                print(f"scanned {join(dir_path, file)}")


def all():
    tests_summary()
    docs()
    man_pages()
    vasm()
    site()


def max_size():
    maximum_size = 0

    for command_name in commands:
        if len(command_name) > maximum_size:
            maximum_size = len(command_name)

    return maximum_size


def help_make():
    print(
        """
usage: x.py [DIRECTIVE...]

a directive can be any of the following:
"""
    )

    # sort command by how many reliers they have
    new_commands = sorted(
        commands, key=lambda command: len(commands[command]["relies_on"]), reverse=False
    )
    for command in new_commands:
        print(f"\t{command.ljust(max_size() +2)}{commands[command]['description']}")

        if "relies_on" in commands[command] and len(commands[command]["relies_on"]) > 0:
            print(
                f"{''.ljust(max_size() +12)}relies on steps: {Style.BRIGHT}{', '.join([x.__name__ for x in commands[command]['relies_on']])}{Style.RESET_ALL}"
            )

    exit(0)


commands = {
    "tests": {
        "runner": tests,
        "description": "Builds the tests suite",
        "relies_on": [ensure_zig],
    },
    "tests-summary": {
        "runner": tests_summary,
        "description": "Builds the tests suite",
        "relies_on": [ensure_zig],
    },
    "clean": {
        "runner": clean,
        "description": "Cleans any zig cache files",
        "relies_on": [],
    },
    "docs": {
        "runner": docs,
        "description": "Builds the documentation",
        "relies_on": [ensure_asciidoc],
    },
    "all": {
        "runner": None,
        "description": "Builds everything including stylist, vasm.adoc, and docs and runs tests silently",
        "relies_on": [ensure_zig, ensure_asciidoc, tests, docs, man_pages, vasm, site],
    },
    "help": {
        "runner": help_make,
        "description": "prints the help menu.",
        "relies_on": [],
    },
    "build": {
        "runner": vasm,
        "description": "Builds the VASM program.",
        "relies_on": [ensure_zig],
    },
    "vasm": {
        "runner": vasm,
        "description": "(alias to build)",
        "relies_on": [ensure_zig],
    },
    "site": {
        "runner": site,
        "description": "Builds the website documentation",
        "relies_on": [ensure_asciidoc],
    },
    "man-pages": {
        "runner": man_pages,
        "description": "Builds the manual pages (also places them in the docs/man directory)",
        "relies_on": [ensure_asciidoc],
    },
    "ensure-zig": {
        "runner": ensure_zig,
        "description": "Ensures that zig is installed",
        "relies_on": [],
    },
    "ensure-asciidoc": {
        "runner": ensure_asciidoc,
        "description": "Ensures that asciidoctor is installed",
        "relies_on": [],
    },
    "open-website": {
        "runner": open_website,
        "description": "Opens the website",
        "relies_on": [],
    },
    "find-bad-lines": {
        "runner": find_bad_lines,
        "description": "Finds any std.debug.print() calls in the source code",
        "relies_on": [],
    },
}

for arg in argv[1:]:
    if commands.get(arg) is not None:
        for relier in commands[arg]["relies_on"]:
            if relier is not None:
                print(
                    f"{Fore.MAGENTA}running dependent step{Fore.RESET}: {relier.__name__}"
                )
                relier()

        # headless commands are allowed
        if commands[arg]["runner"] is not None:
            commands[arg]["runner"]()
    else:
        print(f"unknown build directive: {arg}")
