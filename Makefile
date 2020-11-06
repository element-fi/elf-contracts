all    :; clean build test
build  :; dapp build
init   :; dapp update; npm install
fmt    :; npm run prettier
fmt-ci :; npm run style-check
lint   :; npm run solhint
clean  :; dapp clean
test   :; dapp build; hevm dapp-test --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
test-live :; hevm dapp-test --rpc=YOUR-RPC --json-file=out/dapp.sol.json --dapp-root=. --verbose 1