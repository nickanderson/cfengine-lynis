MASTERFILES ?= /var/cfengine/masterfiles
PROJECT=$(shell basename $(CURDIR) )
INSTALL_TARGET=${MASTERFILES}/services/${PROJECT}
FILES=$(shell find .)
install: ${FILES}
	mkdir -p ${INSTALL_TARGET}/
	rsync -avz --exclude \.#.* ${CURDIR}/* ${INSTALL_TARGET}/
	find ${INSTALL_TARGET}/ -type f | xargs chmod 600
	find ${INSTALL_TARGET}/ -type d | xargs chmod 700
	echo "Don't forget to include the policy in inputs!"
	echo "Try the augments file (def.json)"
	echo '{"inputs": [ "services/${PROJECT}/policy/main.cf" ]}'

uninstall:
	# Remove deployed policy
	rm -rf $(DEPLOY_DIR)
