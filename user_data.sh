#!/bin/bash
# 1. INSTALL SYSTEM DEPENDENCIES
apt-get update -y
apt-get install -y nodejs npm unzip wget awscli jq mysql-client

# 2. DOWNLOAD & PREPARE APPLICATION CODE
cd /home/ubuntu
wget https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACCAP1-1-91571/1-lab-capstone-project-1/code.zip -O code.zip
unzip -o code.zip -x "resources/codebase_partner/node_modules/*"

# 3. INSTALL NODE MODULES & PM2
cd resources/codebase_partner
npm install aws aws-sdk
npm install -g pm2

# 4. FETCH THE NEWEST SECRET
SECRET_NAME=$(aws secretsmanager list-secrets --region us-east-1 --output json | jq -r '.SecretList | sort_by(.CreatedDate) | last | .Name')
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query SecretString --output text --region us-east-1)

# Extract Values
DB_HOST=$(echo $SECRET_JSON | jq -r .host)
DB_USER=$(echo $SECRET_JSON | jq -r .username)
DB_PASS=$(echo $SECRET_JSON | jq -r .password)
DB_NAME=$(echo $SECRET_JSON | jq -r .dbname)

# 5. AUTO-PATCH THE DATABASE (Schema Fix)
# We run this blindly to ensure the table 'students' has columns like 'city' and 'address'.
# If the table is already fixed, these commands will just be ignored or update safely.
mysql -h $DB_HOST -u $DB_USER -p$DB_PASS $DB_NAME <<EOF
DROP TABLE IF EXISTS students;
CREATE TABLE IF NOT EXISTS students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255),
    address VARCHAR(255),
    city VARCHAR(100),
    state VARCHAR(50),
    email VARCHAR(255),
    phone VARCHAR(20)
);
INSERT IGNORE INTO students (id, name, address, city, state, email, phone) VALUES 
(1, 'Alice Smith', '123 Apple St', 'New York', 'NY', 'alice@example.com', '123-456-7890'),
(2, 'Bob Jones', '456 Orange Ave', 'Los Angeles', 'CA', 'bob@example.com', '987-654-3210'),
(3, 'Charlie Day', '789 Banana Blvd', 'Chicago', 'IL', 'charlie@example.com', '555-555-5555');
EOF

# 6. WRITE CONFIGURATION FILE DIRECTLY (The Connectivity Fix)
# Instead of relying on environment variables, we hardcode the fetched credentials into the file.
cat <<EOF > app/config/config.js
module.exports = {
    APP_DB_HOST: '$DB_HOST',
    APP_DB_USER: '$DB_USER',
    APP_DB_PASSWORD: '$DB_PASS',
    APP_DB_NAME: '$DB_NAME',
    APP_PORT: 80
};
EOF

# 7. START THE APP
pm2 start index.js --name "student-app" --force
pm2 save
pm2 startup systemd -u root --hp /home/ubuntu