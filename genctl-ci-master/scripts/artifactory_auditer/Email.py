#!/usr/bin/env python3
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
#   Description: 
#       script to send email notifications
#
import os
from smtplib import SMTP
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from email.header import Header
from email.utils import formataddr
import sys

# Constants
_CI_EMAIL_NAME = "clconc"
_CI_EMAIL = "clconc@us.ibm.com"
_HOST = "us.ibm.com"

class Email:
    """
    Class for sending emails
    """
    def __init__(self):
        # Create smtp server
        self.e_server = SMTP(host=_HOST)
        self.e_server.starttls()
        self.container = MIMEMultipart('alternative')

    def sendEmail(self, recipientList, subject, body, filename=None, html=False):
        """
        Send email to a recipientList
        Args:
            recipientList (list): list of recipients to send the email to
            subject (string): email title
            body (string): the body of the email
            filename (string, optional): optional attachment file. Defaults to None.
            html (bool, optional): optional html email body format. Defaults to False.
        """
        if not isinstance(recipientList, list):
            print('Recipients is not a valid list')
            sys.exit(1)
        self.container['Subject'] = subject
        self.container['FROM'] = formataddr((str(Header(_CI_EMAIL_NAME, 'utf-8')), _CI_EMAIL))
        self.container['TO'] = ",".join(recipientList)
        self.container.add_header('reply-to', _CI_EMAIL)
        self.container.attach(MIMEText(body, 'plain'))

        if html:
            self.container.attach(MIMEText(body, 'html'))
        
        # Section for attatchments 
        if filename:
            with open(filename) as fil:
                part = MIMEApplication(
                    fil.read(),
                    Name=os.path.basename(fil.name)
                )
                # After the file is closed
                part['Content-Disposition'] = 'attachment; filename="{}"'.format(os.path.basename(fil.name))
                self.container.attach(part)

        # Send email to recipients
        try:
            print('Sending email..')
            self.e_server.sendmail(_CI_EMAIL, recipientList, self.container.as_string()) 
        except:
            print('Error, an email could not be sent')
            raise