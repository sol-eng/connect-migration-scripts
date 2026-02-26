# connect-migration-scripts

This repository is a work in progress to help migration of content from a Posit Connect Server to another.

Main use case here is where content from one server is merged into an existing server that prevents an official migration. The approach here also can be used to selectively migrate pieces of content. 

The repository has two main folders 

## connect

This contains a docker-compose enviroment that spins up two Posit connect servers where one is populated with some test users and deployments, the other remains empty. There also is a package manager container for conveniency reasons. 
 
## migrate

Here there is the R scripts that use the Connect API for the migration work: 

* `download-bundle.r` is getting stock of the old server and downloads relevant data such as user and group lists, inventory and metadata for any deployed content, and eventually will download all (or selected) application bundles to a defined folder
* `upload-bundle+ownership.r` is using the information created above and uploads all application bundle to the new connect server, adds the original permissions, adds vanity URLs and tags all migrated content with `migrated` tag. If no external user management is used, the script also can be used to automatically re-create any missing users and groups on the new connect server.

For users that use LDAP the user & group creation process needs to be modified. For users with SAML or OIDC authentication (but no LDAP) there is no option to create the users and groups automatically. 
