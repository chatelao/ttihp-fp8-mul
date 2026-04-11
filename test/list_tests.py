import importlib
import sys
import os

def list_tests(module_name):
    try:
        sys.path.insert(0, os.getcwd())
        module = importlib.import_module(module_name)
        tests = []
        for name in dir(module):
            obj = getattr(module, name)
            if obj.__class__.__name__ == "Test":
                tests.append(name)
        return tests
    except Exception as e:
        print(f"Error importing {module_name}: {e}", file=sys.stderr)
        return []

if __name__ == "__main__":
    for arg in sys.argv[1:]:
        for test in list_tests(arg):
            print(test)
