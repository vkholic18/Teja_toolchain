
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2020
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
#    Contains PipelineMeta class which provides and interface to retireve
#    metadata from the pipeline
#

from git import Repo

class PipelineMeta:
    """
    This class represents the metadata of the pipeline
    It acts as a translator between the CI system specific locations for
    metadata and CI-system-agnostic python tools
    """

    def __init__(self, wsroot):
        self.wsroot = wsroot
        self.meta = {}

    @property
    def author_email(self):
        """
        :type: string
        """
        if 'author_email' not in self.meta.keys():
            self._parse_author_email()

        return self.meta['author_email']

    def _parse_author_email(self):
        """
        Uses git show to determine the author of the last commit
        """
        repo = Repo(self.wsroot)
        head_commit = repo.head.commit

        email = repo.git.show("-s", "--format=%ae", head_commit.hexsha)
        self.meta['author_email'] = email
