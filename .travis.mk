#
# Travis CI rules
#

DOCKER_IMAGE:=packpack/packpack:ubuntu-zesty

all: package

package:
	git clone https://github.com/packpack/packpack.git packpack
	./packpack/packpack

test: test_$(TRAVIS_OS_NAME)

# Redirect some targets via docker
test_linux: docker_test_ubuntu
coverage: docker_coverage_ubuntu
source: docker_source_ubuntu
source_deploy: docker_source_deploy_ubuntu

docker_%:
	mkdir -p ~/.cache/ccache
	docker run \
		--rm=true --tty=true \
		--volume "${PWD}:/tarantool" \
		--volume "${HOME}/.cache:/cache" \
		--workdir /tarantool \
		-e XDG_CACHE_HOME=/cache \
		-e CCACHE_DIR=/cache/ccache \
		-e COVERALLS_TOKEN=${COVERALLS_TOKEN} \
		${DOCKER_IMAGE} \
		make -f .travis.mk $(subst docker_,,$@)

deps_ubuntu:
	sudo apt-get update && apt-get install -y -f \
		build-essential cmake coreutils sed \
		libreadline-dev libncurses5-dev libyaml-dev libssl-dev \
		libcurl4-openssl-dev binutils-dev \
		python python-pip python-setuptools python-dev \
		python-msgpack python-yaml python-argparse python-six python-gevent \
		lcov ruby

test_ubuntu: deps_ubuntu
	cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo
	make -j8
	cd test && /usr/bin/python test-run.py

deps_osx:
	brew install openssl readline --force
	sudo pip install python-daemon PyYAML
	sudo pip install six==1.9.0
	sudo pip install gevent==1.1.2

test_osx: deps_osx
	cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo
	# Increase the maximum number of open file descriptors on macOS
	sudo sysctl -w kern.maxfiles=20480 || :
	sudo sysctl -w kern.maxfilesperproc=20480 || :
	sudo launchctl limit maxfiles 20480 || :
	ulimit -S -n 20480 || :
	ulimit -n
	make -j8
	cd test && python test-run.py unit/ app/ app-tap/ box/ box-tap/

source_ubuntu: deps_ubuntu
	git clone https://github.com/packpack/packpack.git packpack
	make -f ./packpack/pack/Makefile TARBALL_COMPRESSOR=gz tarball

source_deploy_ubuntu:
	sudo apt-get update && apt-get install -y awscli
	aws --endpoint-url "${AWS_S3_ENDPOINT_URL}" s3 \
		cp build/*.tar.gz "s3://tarantool-${TRAVIS_BRANCH}-src/" \
		--acl public-read
