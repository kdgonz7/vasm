from sys import argv
from os import system as internal_system, makedirs, listdir, walk
from os.path import basename, join
from shutil import which
from colorama import Fore, Style

# The format used to generate web docs
WEB_FORMAT = "html"

# The format used for the manual pages
MAN_FORMAT = "manpage"

# The asciidoctor binary location
ASCIIDOCTOR = which("asciidoctor")

# The zig binary location
ZIG = which("zig")

if ZIG is None:
    print(
        f"{Fore.YELLOW}{Style.DIM}VASM requires Zig to be installed.{Style.RESET_ALL}{Fore.RESET}"
    )

    exit(1)


def system(command: str) -> None:
    command_fragments = command.split(" ")
    command_fragments[0] = (
        f"{Fore.BLACK}{Style.DIM}{basename(command_fragments[0])}{Style.RESET_ALL}"
    )

    print(
        f"{' '.join(command_fragments)}",
        flush=True,
    )
    internal_system(command)


def ensure_dir(path):
    makedirs(path, exist_ok=True)


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
    """Builds the documentation."""
    if ASCIIDOCTOR is None:
        print(
            f"{Fore.YELLOW}{Style.DIM}VASM requires Asciidoctor to be installed.{Style.RESET_ALL}{Fore.RESET}"
        )

        exit(1)

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

    for command in commands:
        print(f"\t{command.ljust(max_size() +2)}{commands[command]['description']}")

    exit(0)


commands = {
    "tests": {
        "runner": tests,
        "description": "Builds the tests suite",
    },
    "tests-summary": {
        "runner": tests_summary,
        "description": "Builds the tests suite",
    },
    "clean": {
        "runner": clean,
        "description": "Cleans any zig cache files",
    },
    "docs": {
        "runner": docs,
        "description": "Builds the documentation",
    },
    "all": {
        "runner": all,
        "description": "Builds everything including stylist, vasm.adoc, and docs and runs tests silently",
    },
    "help": {
        "runner": help_make,
        "description": "prints the help menu.",
    },
    "build": {
        "runner": vasm,
        "description": "Builds the VASM program.",
    },
    "vasm": {
        "runner": vasm,
        "description": "(alias to build)",
    },
    "site": {
        "runner": site,
        "description": "Builds the website documentation",
    },
    "man-pages": {
        "runner": man_pages,
        "description": "Builds the manual pages (also places them in the docs/man directory)",
    },
}

for arg in argv[1:]:
    if commands.get(arg) is not None:
        commands[arg]["runner"]()
    else:
        print(f"unknown build directive: {arg}")
