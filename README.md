[![Foundry][foundry-badge]][foundry]
[![AGPL License](https://img.shields.io/badge/license-AGPL-blue.svg)](http://www.gnu.org/licenses/agpl-3.0)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

# 🔮 Puppet Finance Smart Contracts

This is the main Puppet Finance public smart contract repository.


## 🔧 Set up local development environment

### Requirements

-   [Docker Desktop](https://www.docker.com/products/docker-desktop/)

### Local Setup Steps

```sh
# clone repo
git clone https://github.com/GMX-Blueberry-Club/puppet-contracts.git

# cd into cloned repo
cd puppet-contracts

# create a .env file
touch .env

# add your Arbitrum RPC URL to the .env file
echo "ARBITRUM_RPC_URL=<YOUR_ARBITRUM_RPC_URL_LINK>" >> .env

# build the docker image
docker build -t puppet .

# run the image with a volume to the current working directory and enter the container
docker run -it -v "/${PWD}:/puppet-contracts" puppet bash

# build the project
forge build
```
### Running Tests

To run tests, run the following commands

```sh
# run tests
forge test

# run slither
slither .
```
## 📜 Contract Addresses

[Deployed Addresses](TODO-URL)

## 📖 Documentation

[Documentation](TODO-URL)


## 💗 Contributing

Contributions are always welcome!

Come say hey in our [Discord server](TODO-URL)

