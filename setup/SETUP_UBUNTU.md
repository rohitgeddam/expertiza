Set up system to run Expertiza
=================================

**Target Audience:** Expertiza developers who are setting up a new `Ubuntu` server to run Expertiza on. A basic understanding of the Linux command line interface is required for debugging purposes. <br>

**You currently have**: A fresh `Ubuntu` system/server, referred to as the **Target server**. <br>

**You will end with**: A fully configured development environment for Expertiza on the Target server. <br>

**Purpose of the Guide**: The purpose of the guide is to take the user from a fresh system to a complete development environment for Expertiza. The environment can be used to run the `Rails server`.


## STEP 1 : Initialize Target Server.
**Where** : These tasks are performed on your Target Server.<br>

Next, you need to initialize the Target Server to allow for remote access via [GitHub Actions](https://docs.github.com/en/actions/learn-github-actions/understanding-github-actions). Follow these steps to set up SSH keys:

1. Generate an SSH key pair if you haven't already. You can learn more about [ssh-keygen here](https://www.ssh.com/academy/ssh/keygen).
    ```bash
    ssh-keygen
    ```
2. Export the public key to the `authorized_keys` file to allow for remote login.
    ```bash
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    ```
3. Add private key from `~/.ssh/id_rsa` to your repository's secret keys with name <strong>`SSH_PRIVATE_KEY`</strong> - [Creating encrypted secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets#creating-encrypted-secrets-for-a-repository)

4. Add the Target Server's IP address and your user as secrets to your repository as SSH_HOST and SSH_USER, respectively.
   ```
   Name - SSH_HOST
   Secret - 152.7.99.76 <Your Server's IP>
   
   Name - SSH_USER
   Secret - amundra <Your Server's user>
   ```

    <img width="1136" alt="Screenshot 2022-11-18 at 5 14 11 PM" src="https://user-images.githubusercontent.com/20452032/202812339-d7b3927d-8fd7-4094-afba-65b2063eed13.png">

5. Modify the **`user`** and **`ruby_version`** variables in the ansible [playbook](https://github.com/expertiza/expertiza/blob/main/setup/setup_playbook_ubuntu.yml) to match your Expertiza user and the ruby version you would like to install.
    ```yml
    ---
    - name: Setup Expertiza System
      hosts: node
      become: true

      vars:
        user: amundra
        user_home: "/home/{{ user }}"
        app_root: "{{ user_home }}/expertiza"
        ruby_version: 2.4
    ```

## Step 2 : Setting Up the Target server Using Ansible Playbook Github Action.
**Where** : This action is performed on your Github Repository.<br>

To complete this step, you will need to run the [remote-system-setup.yml](https://github.com/expertiza/expertiza/blob/main/.github/workflows/remote-system-setup.yml) GitHub Action. To do so, navigate to the Actions tab in your repository and choose the Ansible System Setup workflow. Once the workflow is running, the Target Server will be set up according to the specifications in this [playbook](https://github.com/mundra-ankur/expertiza/blob/main/setup/setup_playbook_ubuntu.yml) <br>

   <img width="1436" alt="action" src="https://user-images.githubusercontent.com/20452032/201730226-99131257-0287-4ab9-b625-abecabde9ef6.png"> <br>

## Step 3: Target Server Configuration
**Note:** These are the manual steps that must be performed on the target server in order to complete the set up and configure the application. These steps should be followed exactly as written and are not optional.

1. **[Change](https://linuxhint.com/change-mysql-password-ubuntu-22-04/)** the MySQL database password

2. **Change** the database password in `config/database.yml` with `YOURNEWPASSWORD`  (which is currently blank by default).

3. Create the required databases by running the following commands, run `mysql -u root -p` then
    ```sql
    CREATE DATABASE expertiza_production;
    CREATE DATABASE expertiza_development;
    CREATE DATABASE expertiza_test;
    ```
4. Run `bundle install` to install all the required dependencies.

5. Load the database schema and run the migrations. Choose the appropriate environment (`production`, `development`, or `test`) when running the commands:
    ```bash
    RAILS_ENV=production bin/rake db:schema:load 
    RAILS_ENV=production bin/rake db:migrate
    ```
    Replace `production` with `development` or `test` as needed for the respective environments.

6. Start rails server, run `rails server`


# Video Demonstration
This is a demonstration for setup on `RHEL System` and consists of more steps than required for an `Ubuntu` system but flow is almost same for both OS, **start at 5:10**. 

https://user-images.githubusercontent.com/20452032/219795863-99c048ec-045f-4737-aab1-e29a704b9469.mp4


