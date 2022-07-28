user=$1
useradd $user
echo $user | passwd --stdin $user
chmod -R o-r /assets
