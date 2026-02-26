#!/bin/bash

set -x 

head -c 32 /dev/random | base64 > /tmp/secret.key

if [[ `hostname` == "connect" ]]; then 
    sed -i 's#^; Address.*#Address="http://localhost:3939"#' /etc/rstudio-connect/rstudio-connect.gcfg
else
    sed -i 's#^; Address.*#Address="http://localhost:3940"#' /etc/rstudio-connect/rstudio-connect.gcfg
fi


/opt/rstudio-connect/bin/connect --config /etc/rstudio-connect/rstudio-connect.gcfg &

/opt/rstudio-connect/bin/license-manager activate "$RSC_LICENSE"

sleep 5

if [[ `hostname` == "connect" ]]; then 
    CONNECT_URL="http://connect:3939"
else
    CONNECT_URL="http://connect_new:3939"
fi

if [ ! -f /var/lib/rstudio-connect/connect-bootstrap.key ]; then 
    
    rsconnect bootstrap --raw --server $CONNECT_URL --jwt-keypath /tmp/secret.key \
        > /var/lib/rstudio-connect/connect-bootstrap.key


    API_KEY=`cat /var/lib/rstudio-connect/connect-bootstrap.key`

    DATA='{
    "email": "admin@connect.org",
    "first_name": "Admin",
    "last_name": "User",
    "user_role": "administrator",
    "username": "adminuser"
    }'

    curl --silent --show-error -L --max-redirs 0 --fail \
        -X POST \
        -H "Authorization: Key ${API_KEY}" \
        --data-raw "${DATA}" \
        "${CONNECT_URL}/__api__/v1/users" > /tmp/curl.log

    kill `pgrep connect`  

    /opt/rstudio-connect/bin/usermanager transfer --source-username __bootstrap_admin__  --target-username adminuser --api-keys --delete --yes

    /opt/rstudio-connect/bin/connect --config /etc/rstudio-connect/rstudio-connect.gcfg &

    sleep 5

    for i in 1 2 3 
    do 
        DATA="{
        \"email\": \"user$i@connect.org\",
        \"first_name\": \"User\",
        \"last_name\": \"Num$i\",
        \"user_role\": \"publisher\",
        \"username\": \"user$i\"
        }"

        # Create the user and capture the guid
        USER_GUID=$(curl --silent --show-error -L --max-redirs 0 --fail \
            -X POST \
            -H "Authorization: Key ${API_KEY}" \
            --data-raw "${DATA}" \
            "${CONNECT_URL}/__api__/v1/users" | jq -r '.guid')

        # Create an API key for the user
        KEY_DATA="{\"name\": \"default-key\"}"

        API_KEY_RESPONSE=$(curl --silent --show-error -L --max-redirs 0 --fail \
            -X POST \
            -H "Authorization: Key ${API_KEY}" \
            --data-raw "${KEY_DATA}" \
            "${CONNECT_URL}/__api__/v1/users/${USER_GUID}/keys")

        # Extract the key and write to user's home directory
        USER_API_KEY=$(echo "${API_KEY_RESPONSE}" | jq -r '.key')
        mkdir -p /home/user${i}
        echo "${USER_API_KEY}" > /home/user${i}/.connect-api-key
        chown user${i}:user${i} /home/user${i}/.connect-api-key 2>/dev/null
        chmod 600 /home/user${i}/.connect-api-key
        echo "${USER_GUID}" > /home/user${i}/.connect-guid
        chown user${i}:user${i} /home/user${i}/.connect-guid 2>/dev/null
        chmod 600 /home/user${i}/.connect-guid

    done

    if [[ `hostname` == "connect" ]]; then 
        # Create groups
        GROUP1_DATA='{"name": "group1", "description": "Group 1"}'
        curl --silent --show-error -L --max-redirs 0 --fail \
            -X POST \
            -H "Authorization: Key ${API_KEY}" \
            --data-raw "${GROUP1_DATA}" \
            "${CONNECT_URL}/__api__/v1/groups" > /tmp/group1.log

        GROUP2_DATA='{"name": "group2", "description": "Group 2"}'
        curl --silent --show-error -L --max-redirs 0 --fail \
            -X POST \
            -H "Authorization: Key ${API_KEY}" \
            --data-raw "${GROUP2_DATA}" \
            "${CONNECT_URL}/__api__/v1/groups" > /tmp/group2.log

        # Add adminuser to group1
        GROUP1_GUID=$(curl --silent --show-error -L --max-redirs 0 --fail \
            -H "Authorization: Key ${API_KEY}" \
            "${CONNECT_URL}/__api__/v1/groups?prefix=group1" | \
            python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['guid'] if data['results'] else '')")
        
        ADMINUSER_GUID=$(curl --silent --show-error -L --max-redirs 0 --fail \
            -H "Authorization: Key ${API_KEY}" \
            "${CONNECT_URL}/__api__/v1/users?prefix=adminuser" | \
            python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['guid'] if data['results'] else '')")
        
        if [[ -n "$GROUP1_GUID" && -n "$ADMINUSER_GUID" ]]; then
            echo "Adding adminuser ($ADMINUSER_GUID) to group1 ($GROUP1_GUID)"
            curl --silent --show-error -L --max-redirs 0 --fail \
                -X POST \
                -H "Authorization: Key ${API_KEY}" \
                -H "Content-Type: application/json" \
                --data-raw "{\"user_guid\": \"${ADMINUSER_GUID}\"}" \
                "${CONNECT_URL}/__api__/v1/groups/${GROUP1_GUID}/members" > /tmp/add_adminuser_to_group1.log
            echo "Added adminuser to group1"
        else
            echo "Error: Could not find group1 or adminuser GUIDs"
            echo "GROUP1_GUID: $GROUP1_GUID"
            echo "ADMINUSER_GUID: $ADMINUSER_GUID"
        fi

        # Add user3 to group2
        GROUP2_GUID=$(curl --silent --show-error -L --max-redirs 0 --fail \
            -H "Authorization: Key ${API_KEY}" \
            "${CONNECT_URL}/__api__/v1/groups?prefix=group2" | \
            python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['guid'] if data['results'] else '')")
        
        USER3_GUID=$(curl --silent --show-error -L --max-redirs 0 --fail \
            -H "Authorization: Key ${API_KEY}" \
            "${CONNECT_URL}/__api__/v1/users?prefix=user3" | \
            python3 -c "import sys, json; data=json.load(sys.stdin); print(data['results'][0]['guid'] if data['results'] else '')")
        
        if [[ -n "$GROUP2_GUID" && -n "$USER3_GUID" ]]; then
            echo "Adding user3 ($USER3_GUID) to group2 ($GROUP2_GUID)"
            curl --silent --show-error -L --max-redirs 0 --fail \
                -X POST \
                -H "Authorization: Key ${API_KEY}" \
                -H "Content-Type: application/json" \
                --data-raw "{\"user_guid\": \"${USER3_GUID}\"}" \
                "${CONNECT_URL}/__api__/v1/groups/${GROUP2_GUID}/members" > /tmp/add_user3_to_group2.log
            echo "Added user3 to group2"
        else
            echo "Error: Could not find group2 or user3 GUIDs"
            echo "GROUP2_GUID: $GROUP2_GUID" 
            echo "USER3_GUID: $USER3_GUID"
        fi
    fi

    if [[ `hostname` == "connect" ]]; then 
    # Set up adminuser with deployment capabilities

    sudo -u adminuser bash << EOF
    pip install rsconnect-python

    R_VERSION=4.3.3
    cd /tmp && git clone https://github.com/sol-eng/r-examples.git 
    mkdir -p ~/R/x86_64-pc-linux-gnu-library/4.3
    /opt/R/\${R_VERSION}/bin/R -q -e 'install.packages("pak")'
    /opt/R/\${R_VERSION}/bin/R -q -e 'pak::pak(c("rmarkdown","rsconnect","dplyr","connectapi"))' 
    /opt/R/\${R_VERSION}/bin/R -q -e 'rsconnect::addServer("http://connect:3939",name="my-psc")'
    /opt/R/\${R_VERSION}/bin/R -q -e "rsconnect::connectApiUser(account='adminuser', server='my-psc', apiKey='${API_KEY}')"

    # deploy R shiny app
    /opt/R/\${R_VERSION}/bin/R -q -e 'rsconnect::deployApp(appName="test",appDir="/tmp/r-examples/shiny-penguins", manifestPath="/tmp/r-examples/shiny-penguins/manifest.json")' >& ~/r-shiny.log 
  
    pushd /tmp/r-examples/shiny-penguins
    sed -i 's/Distribution/distribution/' app.R
    /opt/R/\${R_VERSION}/bin/R -q -e 'rsconnect::deployApp(appName="test",appDir="/tmp/r-examples/shiny-penguins", manifestPath="/tmp/r-examples/shiny-penguins/manifest.json")' >& ~/r-shiny.log 
    sed -i 's/Antarctica/Arctica/' app.R
    /opt/R/\${R_VERSION}/bin/R -q -e 'rsconnect::deployApp(appName="test",appDir="/tmp/r-examples/shiny-penguins", manifestPath="/tmp/r-examples/shiny-penguins/manifest.json")' >& ~/r-shiny.log 
    popd


    CONNECT_API_KEY="${API_KEY}" /opt/R/\${R_VERSION}/bin/R -q -e '
        library(connectapi)
        client <- connect(server = "http://connect:3939", api_key = Sys.getenv("CONNECT_API_KEY"))
        app <- get_content(client, name = "test")
        app_item <- content_item(client, app\$guid[1])
        user2 <- get_users(client, prefix = "user2")
        content_add_user(app_item, user2\$guid[1], role = "owner")
        user3 <- get_users(client, prefix = "user3")
        content_add_user(app_item, user3\$guid[1], role = "viewer")
        group1 <- get_groups(client, prefix = "group1")
        content_add_group(app_item, group1\$guid, role="viewer")
        # Transfer ownership to user2
        app_item <- content_update(app_item, owner_guid = user2\$guid[1])
        set_environment_all(
            app_item,
            TEST_ENV_1 = "VALUE_1",
            TEST_ENV_2 = "VALUE_2"
        )

        set_vanity_url(app_item, "my-shiny")

        # Remove adminuser from the content
        admin <- get_users(client, prefix = "adminuser")
        content_delete_user(app_item, admin\$guid[1])
        '

    /opt/R/\${R_VERSION}/bin/R -q -e 'rsconnect::deployDoc("/tmp/r-examples/rmd-penguins/report/report.Rmd", manifestPath="/tmp/r-examples/rmd-penguins/report/manifest.json")' >& ~/rmd-deploy.log 

    CONNECT_API_KEY="${API_KEY}" /opt/R/\${R_VERSION}/bin/R -q -e '
        library(connectapi)
        client <- connect(server = "http://connect:3939", api_key = Sys.getenv("CONNECT_API_KEY"))
        app <- get_content(client, name = "report")
        app_item <- content_item(client, app\$guid[1])
        user1 <- get_users(client, prefix = "user1")
        content_add_user(app_item, user1\$guid[1], role = "owner")
        user3 <- get_users(client, prefix = "user3")
        content_add_user(app_item, user3\$guid[1], role = "viewer")
        group2 <- get_groups(client, prefix = "group2")
        content_add_group(app_item, group2\$guid, role="viewer")
        group1 <- get_groups(client, prefix = "group1")
        content_add_group(app_item, group1\$guid, role="owner")
        # Transfer ownership to user1
        app_item <- content_update(app_item, owner_guid = user1\$guid[1])

        set_environment_all(
            app_item,
            REPORT_ENV_1 = "VALUE_1",
            REPORT_ENV_2 = "VALUE_2",
            REPORT_ENV_3 = "VALUE_3",
            REPORT_ENV_4 = "VALUE_4"
        )
        set_vanity_url(app_item, "rmd-doc")

        # Remove adminuser from the content
        admin <- get_users(client, prefix = "adminuser")
        content_delete_user(app_item, admin\$guid[1])
        '

    cd /tmp/
    git clone https://github.com/sol-eng/python-examples.git
    /usr/local/bin/rsconnect deploy shiny /tmp/python-examples/shiny-income-share -s http://connect:3939 -k $API_KEY >& ~/py-shiny.log 

    CONNECT_API_KEY="${API_KEY}" /opt/R/\${R_VERSION}/bin/R -q -e '
        library(connectapi)
        client <- connect(server = "http://connect:3939", api_key = Sys.getenv("CONNECT_API_KEY"))
        app <- get_content(client, name = "shiny-income-share")
        app_item <- content_item(client, app\$guid[1])
        user1 <- get_users(client, prefix = "user1")
        content_add_user(app_item, user1\$guid[1], role = "owner")
        user2 <- get_users(client, prefix = "user2")
        content_add_user(app_item, user2\$guid[1], role = "owner")
        user3 <- get_users(client, prefix = "user3")
        content_add_user(app_item, user3\$guid[1], role = "viewer")
        # Transfer ownership to user1
        app_item <- content_update(app_item, owner_guid = user2\$guid[1])

        set_vanity_url(app_item, "income-share")

        # Remove adminuser from the content
        admin <- get_users(client, prefix = "adminuser")
        content_delete_user(app_item, admin\$guid[1])
        '

    /usr/local/bin/rsconnect deploy dash /tmp/python-examples/dash-app -s http://connect:3939 -k $API_KEY >& ~/dash-deploy.log 

    rm -rf /tmp/r-examples /tmp/python-examples
EOF
    fi
fi

kill `pgrep connect` 

sed -i '/\[Bootstrap\]/,$d'  /etc/rstudio-connect/rstudio-connect.gcfg 

/opt/rstudio-connect/bin/connect --config /etc/rstudio-connect/rstudio-connect.gcfg &

while true
do
sleep 20
done  
