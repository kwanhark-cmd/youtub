from .server import run

if __name__ == "__main__":
    import sys

    run(open_browser="--no-browser" not in sys.argv)
