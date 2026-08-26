from setuptools import setup, find_packages

setup(
    name="ci_python_tools",
    version="1.0.0",
    author="CI Team",
    description="Y",
    author_email='Z',
    url='https://github.ibm.com/genctl-cicd/genctl-ci/tree/master/tools/ci_python_tools',
    packages=find_packages(),
    install_requires=[
        'JIRA>=2.0.0,<3.0.0',
    ])