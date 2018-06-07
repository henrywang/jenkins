#!/usr/bin/env python
"""Work for Jenkins CI to get kernel done."""

import os
import time
import argparse
import urllib.request
import urllib.error
from datetime import datetime
import hwlogging
import brewer


def download(logger, url, path):
    """Download kernel."""
    file_name = url.split("/")[-1]
    full_path = os.path.join(path, file_name)
    if os.path.isfile(full_path):
        os.remove(full_path)
    try:
        with urllib.request.urlopen(url) as req:
            total_size = int(req.info()["Content-Length"])
            logger.info("Downloading file size is {}M.".
                        format(total_size/1024/1024))
            insize = 0
            CHUNK = 256 * 1024  # 256K buffer
            with open(full_path, "wb") as f:
                start_time = time.time()
                logger.info("Start downloading {0:} at {1:%Y-%m-%d %H:%M:%S}.".
                            format(file_name,
                                   datetime.fromtimestamp(start_time)))
                for buf in iter(lambda: req.read(CHUNK), b''):
                    if not buf:
                        logger.debug("buf: {}".format(buf))
                    f.write(buf)
                    insize += len(buf)
                    logger.debug("Downloading... {0:.2f}%".
                                 format(insize/total_size * 100))
                end_time = time.time()
                logger.info("End downloading {0:} at {1:%Y-%m-%d %H:%M:%S}.".
                            format(file_name,
                                   datetime.fromtimestamp(end_time)))
                delta_time = end_time - start_time
                logger.info("Totaly spent {:02}:{:02}:{:02}.".
                            format(delta_time//3600,
                                   delta_time % 3600//60,
                                   delta_time % 60))
    except urllib.error.HTTPError as e:
        if hasattr(e, "reason"):
            logger.error("Download failed because {}.".format(e.reason))
        elif hasattr(e, "code"):
            logger.error("Download failed with error code {}.".format(e.code))
    except urllib.error.URLError as e:
        if hasattr(e, "reason"):
            logger.error("Download failed because {}.".format(e.reason))
        elif hasattr(e, "code"):
            logger.error("Download failed with error code {}.".format(e.code))


def main(args):
    """Programe bridger starts from here."""
    # Print all avaliable arguments passed in.
    logger = hwlogging.Logger(__file__).logger
    logger.info("Working on kernel: {0}.".format(args.kernel_name))
    logger.info("Brew API address: {0}.".format(args.brew_api))
    logger.info("Brew task ID: {0}.".format(args.id))
    logger.info("Download path: {0}.".format(args.path))

    brew = brewer.Brewer(args.kernel_name, args.brew_api)
    url = brew.download_url(args.id)

    args.download(logger, url, args.path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Work with kernel.')
    parser.add_argument("kernel_name", metavar="kernel-name", type=str,
                        help="kernel name with format \
                        {kernel-version-release}")
    parser.add_argument("brew_api", metavar="brew-api", type=str,
                        help="brew API URL")
    parser.add_argument("--id", type=int, required=True, help="brew task ID")
    parser.add_argument('--download', action='store_const', const=download,
                        help='download kernel')
    parser.add_argument("--path", type=str, default='./',
                        help="path to store kernel")
    args = parser.parse_args()

    main(args)
