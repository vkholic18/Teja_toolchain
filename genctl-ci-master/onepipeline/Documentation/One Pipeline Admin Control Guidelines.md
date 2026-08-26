# One Pipeline Admin Control Guidelines
#### Access Control Changes and Updates


- Admin Account Holder to rotate Admin Credentials every 90 days. 
- Admin Credentials are not shared with any other entity and also not used for automation purposes. 
- Admin account is MFA enabled.

## Fallback Plan in case of Admin moving out of CI (Internal or External movement)


- Rotate the admin credentials and freeze the former Admin user.
- Old MFA TOTP/Yubikey to be deleted.
- New MFA to be setup pointing to new admin user. 
- Old Admin user account to be disabled from access hub. 
- Announcement to be shared to the internal team(CI) on the change.
- Old Admin user's personal account to be removed from CI internal groups in Access Hub.


## Update Rules 

- There might be some active rules that involve the former Admin. Therefore check approval processes, case assignment rules, validation rules, default case/lead owner and case/lead queues, and then remove or replace the Admin user account.

## Change Record Ownership

- Records shouldn’t be owned by an inactive user so transfer ownership of records to make sure that users can continue to access vital data and keep business moving as usual!

