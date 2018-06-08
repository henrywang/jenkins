#!/usr/bin/env python
"""A Python logging wrapper. Some basic settings are configured."""

import logging
import logging.handlers


class Logger():
    """Python logging wrapper."""

    def __init__(
        self,
        _log_file_name,
        _log_file_path,
        _max_logging_file_size=10485760,
        _max_logging_file_count=5
    ):
        """Init method to assign init value to private properties."""
        self.log_file_name = _log_file_name
        self.log_file_path = _log_file_path
        self.max_logging_file_size = _max_logging_file_size
        self.max_logging_file_count = _max_logging_file_count

    @property
    def logger(self):
        """Public property to return configured logger object."""
        logger = logging.getLogger(self.log_file_name)
        logger.setLevel(logging.DEBUG)

        # Setup log format
        formatter = logging.Formatter(
            "%(levelname)s - %(asctime)s - %(name)s - %(message)s")

        # Create console handler
        ch = logging.StreamHandler()
        ch.setLevel(logging.DEBUG)
        ch.setFormatter(formatter)

        # Create file handler
        fh = logging.handlers.RotatingFileHandler(
            self.log_file_path + self.log_file_name,
            maxBytes=self.max_logging_file_size,
            backupCount=self.max_logging_file_count
        )
        fh.setLevel(logging.INFO)
        fh.setFormatter(formatter)

        # Associate handler with logger
        logger.addHandler(ch)
        logger.addHandler(fh)

        return logger
