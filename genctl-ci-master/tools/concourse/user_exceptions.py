#
# =============================================================================================
# IBM Confidential
# © Copyright IBM Corp. 2019
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

# /usr/local/bin/python3
"""
* misc helper exceptions
"""


###############################################################################
# E X C E P T I O N S #########################################################
###############################################################################

class ConfigError(Exception):
    """
    * Except on configuration issues (ie. hub not installed/configured)
    """

    # Constructor or Initializer
    def __init__( self, value ):
        super(ConfigError, self).__init__()
        self.value = value

    # __str__ is to print() the value
    def __str__( self ) :
        return repr(self.value)


class ExecutionError(Exception):
    """
    * Except on issues running git/hub
    """

    # Constructor or Initializer
    def __init__( self, value):
        super(ExecutionError, self).__init__()
        self.value = value

    # __str__ is to print() the value
    def __str__( self ) :
        return repr(self.value)
