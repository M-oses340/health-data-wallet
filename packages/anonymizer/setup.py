from setuptools import setup, find_packages

setup(
    name="health-data-anonymizer",
    version="1.0.0",
    packages=find_packages(where="src"),
    package_dir={"": "src"},
    install_requires=[
        "presidio-analyzer>=2.2.0",
        "presidio-anonymizer>=2.2.0",
    ],
)
