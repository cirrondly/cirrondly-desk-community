TAG ?= v0.1.0
TAG_MESSAGE ?= $(TAG) - Initial public release

.PHONY: delete-tag recreate-tag

delete-tag:
	-git tag -d $(TAG)
	git push origin :refs/tags/$(TAG)

recreate-tag:
	git tag -a $(TAG) -m "$(TAG_MESSAGE)"
	git push origin $(TAG)