# shopware-railway

Wrapper images that run [Shopware 6](https://github.com/shopware/shopware) on Railway: the web, worker and scheduler in one image
(`Dockerfile.app`), plus MySQL 8.4 (`Dockerfile.db`) and Redis (`Dockerfile.redis`) with the Railway volume permissions handled.

Images: `ghcr.io/bon5co/shopware-railway-app`, `-db`, `-redis`, tagged with the Shopware version.
Used by the Railway template "Shopware".
