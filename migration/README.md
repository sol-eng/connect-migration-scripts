# connect-migration

Simple R script that downloads application bundles from one connect server and uploads them to another. Selection can be made via tags or publisher names. 

# Step 1: Download bundle on source server

In `download-bundle.r`, please add the correct values to 

* `server` name
* `api_key` a Connect API key with admin privileges 
* `my_tag` the tag to be used for identifying content

# Step 2: Run `download-bundle.r`

When running `download-bundle.r`, it will 

1. create a CSV file named `relevant_content.csv` - this file contains all the metadata for the content. 
2. download all the bundles that match the tag

# Step 3: Review `relevant_content.csv`

If you would like to assign different owners to the content to be deployed on the new connect server, please add the usernames in the `owner` column of the csv. If the column remains empty, the user associated wit the api key will automatically become the owner of the content.

# Step 4: Run `upload-bundle+ownership.r`

This final step will re-upload all bundles and - if necessary - realign ownership. Again, please change 
* `server` name
* `api_key` a Connect API key with admin privileges. 


# Appendix 

It is assumed that the code from this github repository will be cloned into a folder on a unix system and `renv` is pre-installed on the version of R to be used. Please note that as long as connectivity to both old and new connect server is ensured, the scripts can be run from any unix server. You may want to restore the environment via `renv::restore()` before running the code. 