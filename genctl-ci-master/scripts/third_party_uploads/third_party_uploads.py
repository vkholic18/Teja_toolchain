#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2022
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#

"""
Description:

Generates a list of images defined in genctl-ci/hack/ci/third-party-third_party_uploads_config.yaml.
Passes the list to the following task to copy them over to Artifactory, reg-prod and ICCR.
"""

import logging
import os
import sys
import yaml
from ci_python_tools import general_tools

# Globals
THIRD_PARTY_UPLOADS = '/../../hack/ci/third_party_uploads_config.yaml'

def create_image_list(THIRD_PARTY_UPLOADS):
    """
    Read the third_party_uploads yaml and create an image list
    """
    image_list_to_upload = list()
    image_str_to_upload = str()

    try:
        config_path = os.path.dirname(sys.argv[0])
        config_file = config_path + THIRD_PARTY_UPLOADS
        with open(config_file) as f:
            uploads_yaml = yaml.safe_load(f)['uploads']

        if uploads_yaml:
            for workspace in uploads_yaml:
                image_list_to_upload.extend(workspace['images'])

            image_str_to_upload = ' '.join([str(image) for image in image_list_to_upload])

    except Exception as exception:
        logger.error(f'Exception while reading the uploads yaml')
        logger.error(exception)
        exit(1)

    return image_str_to_upload


def main():
    """
    Main function
    """
    global logger
    logger = general_tools.set_up_logger(logging.INFO)

    mandatory_args = ['BUILD_ROOT']
    args = general_tools.parse_env(mandatory_args)
    build_root_dir = args['build_root']

    # Create a temp file which will be passed onto tasks/copy-images.yaml
    tmp_file = f'{build_root_dir}/images-to-copy/final_image_list.txt'
    image_str_to_upload = create_image_list(THIRD_PARTY_UPLOADS)

    if image_str_to_upload:
        logger.info(f'Images to upload: {image_str_to_upload}')
        with open(tmp_file, 'w') as f:
            f.write(image_str_to_upload)
    else:
        logger.error('No images found to upload!')
        exit(1)

if __name__ == "__main__":
    main()
