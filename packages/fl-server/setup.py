from setuptools import setup, find_packages

setup(
    name="fl_server",
    version="0.1.0",
    package_dir={"": "src"},
    packages=find_packages(where="src"),
    py_modules=["fl_client", "fl_server", "app"],
)
