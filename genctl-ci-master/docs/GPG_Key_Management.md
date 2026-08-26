# GPG Key Management

Note: This document is intended for use by the DevOps team, and is not a document containing information regarding how to add GPG signing to workspaces. For that information, see the [Build-Meta, Signing & Multi-arch building document](https://confluence.swg.usma.ibm.com:8445/pages/viewpage.action?pageId=227246206).

## Master Key Generation:  
The Master Key was generated in a container based on the `golang-ci:20220629132342-amd64` image, which contains `GnuPG 2.2.20` and `libgcrypt 1.8.5`  
After installing `pinentry` via `dnf install pinentry`, which is required for many key management operations (including generating a key),
`gpg --full-generate-key` was run with the following selections to generate the master key:

```
# Please select what kind of key you want:
4 # RSA (sign only)

# What keysize do you want?
4096

# Please specify how long the key should be valid
0
# 0 = key does not expire

# Real Name:
NextGen VPC CI

# Email Address:
clconc@us.ibm.com

# Comment:
GPG Signing Key

# You selected this USER-ID:
#    "NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>"
```

A password was also added to the key, which will not be listed here for obvious reasons.  

If you are creating a new Master Key, to export it from the system, you would run:  
`gpg -a -o gpg-private-key.key --export-secret-keys`  
`-o` is for output, and specifies the file to write to  
`-a` stands for armor, and results in the output file not being in binary.   
Note that the file will contain all subkeys that are related to the master key as well (unless any subkeys are removed prior to running the command). 

## Sub Key Generation:
### Step 1: Creating the Sub Key:

In order to generate a subkey, there must be a master key loaded into GPG on the system.  
To import a GPG Key into the system, you would run:  
`gpg --import ${key_name}`  
where `${key_name}` refers to the filename of the GPG Master key. 


```
# Enter the GPG interfact for editing keys. You'll note that the symbol will change to `>` at the beginning of each line to indicate that you are in the editing interface
gpg --edit-key "NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>"

# Create a new subkey:
addkey

# Please select what kind of key you want:
4
# (4) RSA (sign only)

# RSA keys may be between 1024 and 4096 bits long.# What keysize do you want? (2048)
4096

# Please specify how long the key should be valid
0
#  0 = key does not expire
```
Some more prompts will come up, asking you to confirm details, and then enter the password.
Note that the password being requested is for the key that you specified in an earlier command - specifically after the `--edit-key` option, which should be the master key.  
The password should be stored in an entry in vault that is separate from the key itself.


In the output text from creating the subkey, the subkey will have its identifier displayed (see below).
Note that to be able to view this identifier again, you would need to enter the `--edit-key` sub-menu (it is not displayed otherwise).  
The output will look something like the following:  
```
sec  rsa4096/ADB1F66AFA78F273
     created: 2022-08-04  expires: never       usage: SC
     trust: ultimate      validity: ultimate
ssb  rsa4096/595B4E7F38034C94
     created: 2022-08-10  expires: never       usage: S
[ultimate] (1). NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>
```
The following section is intended to explain some of the information that is shown above. 

#### Output Details:

“Sec” stands for secret - this is the master key. It is followed by what type of key the master key is, then the identifier for that particular key.  
“ssb” stands for secret subkey - this is the subkey used for signing (in the above example)  

For the “usage:” field’s values, each letter has a corresponding meaning:  
S - Signature  
C - Certificate  
E - Encryption  
A - Authentication  
Which means the key can be used for signing, creating a certification, encryption, and authentication respectively.


### Step 2: Remove the password on the Sub Key
I recommend reading through the entire section before running it - This is because the process is confusing, and understanding what you're going to be doing ahead of time should help make it easier to understand.

Note that this section assumes you are directly continuing from the prior step, and therefore that you are still within the `--edit-key` submenu.  
`passwd`  

The first dialogue box will state that it is to unlock a secret key, which is the master key (you can tell from the key's identifier). We do not want to nor need to unlock the master key, so select "CANCEL" first.  

Another prompt will have come up requesting the password for the sub key. You can determine this because it will contain the sub key's identifier in addition to the master key's identifier.  

Enter the (master key's) password (as the subkey inherited it) and then confirm. 

You will have had another prompt come up, asking for a password to set. This is for the key from the previous prompt (so the subkey). Leave the password field blank, and then click ok. You will get a confirmation box pop up asking you to confirm that you do not want a password, accept this, and be sure to read the rest of the text following this before proceeding further.

The output consists of error messages for keys that __did not__ have their passwords changed. Keys are specified in the format of `MASTER_KEY_IDENTIFIER/SELECTED_KEY_IDENTIFIER`  

Given the following:  
__Master Key__ with an identifier of `1234567890ABCDEF`  
__Sub Key 1__ of __Master Key__ with an identifier of: `1000000000000000`  
__Sub Key 2__ of __Master Key__ with an identifier of: `2000000000000000`  
If you successfully changed the password of __Sub Key 1__, the output would look like:
```
gpg: key 1234567890ABCDEF/1234567890ABCDEF: error changing passphrase: Operation cancelled
gpg: key 1234567890ABCDEF/2000000000000000: error changing passphrase: Operation cancelled
```

Note that there will NOT be a confirmation regarding the key(s) passwords you changed.  
Confirm that the output is expected for what you intended to do (in other words, verify that what you meant to do is what actually happened).

Next, save the changes made (which also exits the interface for editing keys automatically)  
`save`

### Step 3: Export The Sub Key(s): 
The general form of the command to run is:  
`gpg -a --output ${RepoNameSigningSubKey} --export-secret-subkeys ${SubKeyIdentifier} ${SubKeyIdentifier}!`  
where:  
`--output` writes to the specified filename  
`--export-secret-subkeys` takes in the name of either the Master Key, or a space-separated list of sub-key identifiers, each one ending with “!” To include in the output file.  

Note: It’s a good idea to name the output file corresponding to the key's usage, such as “${RepoName}SigningSubKey”, where ${RepoName}'s value would be based on the purpose the subkey is being generated; for example, if the HostOS team requested a key for signing their packages, "HostOsSigningSubKey".

Given the following example:  
__Master Key__ with an identifier of `1234567890ABCDEF`  
__Sub Key 1__ of __Master Key__ with an identifier of: `1000000000000000`  
__Sub Key 2__ of __Master Key__ with an identifier of: `2000000000000000`  
Where:  
__Sub Key 1__ would be the signing key for a repository called __DuckPond__  
__Sub Key 2__ would be the signing key for a repository called __BeachSand__  

To export the signing subkey for the repositry named __DuckPond__:  
`gpg -a --output DuckPondSigningSubKey --export-secret-subkeys 1000000000000000!`

To export the signing subkey for the repositry named __BeachSand__:  
`gpg -a --output DuckPondSigningSubKey --export-secret-subkeys 2000000000000000!`

to export all sub-keys, we could run either of the following commands:
- `gpg -a --output AllSigningSubKeys --export-secret-subkeys 1234567890ABCDEF`
- `gpg -a --output AllSigningSubKeys --export-secret-subkeys 1000000000000000! 2000000000000000!`  

Note that there will not be output shown for this command either - the output is written to the output file.

## Revocation 

This section is designed to describe the process for revoking a sub key. 

Given the following example:  
__Master Key__ with an identifier of `1234567890ABCDEF`  
__Sub Key 1__ of __Master Key__ with an identifier of: `1000000000000000`  
__Sub Key 2__ of __Master Key__ with an identifier of: `2000000000000000`  
Where:  
__Sub Key 1__ would be the signing key for a repository called __DuckPond__  
__Sub Key 2__ would be the signing key for a repository called __BeachSand__  

```
gpg --edit-key "NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>"
```

Select the sub key that you want to revoke by entering its unique identifier (displayed in the edit-keys submenu when entering, and when using the 'list' command). 
```
key ${sub_key_to_revoke}

# For example, to select the signing sub key for DuckPond, we would run:
key 1000000000000000
```

Revoke the key - interactive. Will ask:
- If you really want to revoke the key
- Reason for revocation
- Comment (try to be detailed)
- Master key's password at the end
```
revkey

# Sample Output:
Do you really want to revoke this subkey? (y/N) y
Please select the reason for the revocation:
  0 = No reason specified
  1 = Key has been compromised
  2 = Key is superseded
  3 = Key is no longer used
  Q = Cancel
Your decision? 1
Enter an optional description; end it with an empty line:
> Revoking key due to it being stolen. 
> This was previously the signing sub key for "DuckPond"
>
Reason for revocation: Key has been compromised
Revoking key due to it being stolen. 
This was previously the signing sub key for "DuckPond"
Is this okay? (y/N) y

sec  rsa4096/1234567890ABCDEF
     created: 2100-01-25  expires: never       usage: SC
     trust: ultimate      validity: ultimate
ssb  rsa4096/1000000000000000
     created: 2100-01-25  expires: never       usage: S
The following key was revoked on 2100-01-25 by RSA key 1234567890ABCDEF NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>
ssb  rsa4096/2000000000000000
     created: 2100-01-25  revoked: 2100-01-26  usage: S
[ultimate] (1). NextGen VPC CI (GPG Signing Key) <clconc@us.ibm.com>
```

Now that the key has been revoked, there are a few more steps:
 - Update the Master Key (in the location where it is stored securely)
   - This is because revoking a sub key changed the Master Key - we want the Master Key to be up-to-date in its storage location.
 - Distribute the updated public key(s) so that the updated one can be used for verifying signatures are valid. 
From [gnupg.org](https://www.gnupg.org/gph/en/manual/c235.html):
> Revoking both subkeys and self-signatures on user IDs adds revocation self-signatures to the key. Since signatures are being added and no material is deleted, a revocation will always be visible to others when your updated public key is distributed and merged with older copies of it. Revocation therefore guarantees that everybody has a consistent copy of your public key.
 - If needed, create a new sub key for the repository the prior sub key was revoked for. 

## Sharing the Public Key

In order to share the public key for the Master Key, we need to generate it 
```
gpg -o master_key.pub --export -a
```
Upload the updated public key
