#!/usr/bin/env python
"""A brew wrapper."""

import re
from xmlrpc.client import ServerProxy
import datetime
import hwlogging


class Brewer():
    """Work with brew to get build information.

    This class provides build info, tags, changelog, and bugs information of
    this build.

    Parameters of this class:
        name: A string representing the build's name ("kernel-3.10.0-825.el7").
        api: Brew API URL ("http://api.brew.com/brewhub").
    """

    def __init__(self, name, api):
        """Init variables and logger."""
        self.name = name
        self._api = api
        self._logger = hwlogging.Logger(__name__).logger

    def _get_proxy(self):
        return ServerProxy(self._api)

    @property
    def build(self):
        """Return a dict of build info.

        {'package_name': 'kernel',
         'extra': None,
         'creation_time': '2017-12-13 10:21:22.163979',
         'completion_time': '2017-12-13 11:53:55.824766',
         'package_id': 1231,
         'id': 632394,
         'build_id': 632394,
         'epoch': None,
         'source': None,
         'state': 1,
         'version': '3.10.0',
         'completion_ts': 1513166035.82477,
         'owner_id': 1474,
         'owner_name': 'raquini',
         'nvr': 'kernel-3.10.0-821.el7',
         'start_time': '2017-12-13 10:21:22.163979',
         'creation_event_id': 17427237,
         'start_ts': 1513160482.16398,
         'volume_id': 0,
         'creation_ts': 1513160482.16398,
         'name': 'kernel',
         'task_id': 14744635,
         'volume_name': 'DEFAULT',
         'release': '821.el7'}.
        """
        return self._get_proxy().getBuild(self.name)

    @property
    def tags(self):
        """Return a tuple of tags of this build.

        ('rhel-7.5-candidate',)
        """
        raw_tags = self._get_proxy().listTags(self.name)
        self._logger.debug("Raw tags fetched from brew {0}"
                           .format(raw_tags))
        return tuple(x['name'] for x in raw_tags)

    @property
    def changelog(self):
        r"""Return a raw changelog dict.

        {'date': '2017-12-26 12:00:00', 'text': "- [scsi] lpfc: Fix crash
        after bad bar setup on driver attachment (Dick Kennedy) [1441965]\n",
        'date_ts': 1514289600, 'author': 'Rafael Aquini <aquini@redhat.com>
        [3.10.0-825.el7]'}
        """
        # Work around log time is not at the same day as build "start_time"
        # Like kernel-3.10.0-512.el7, its log time is 2016-09-30 12:00:00
        # but its build start time is 2016-10-01 03:27:46.300467
        dt_obj = datetime.datetime.strptime(
            self.build["start_time"], "%Y-%m-%d %H:%M:%S.%f")
        dt_delta = dt_obj - datetime.timedelta(days=3)
        dt_delta_str = dt_delta.strftime("%Y-%m-%d %H:%M:%S")
        self._logger.debug(
            "Build was built at {0}, changelogs will be fetched after {1}."
            .format(dt_obj, dt_delta_str)
        )
        changelogs = self._get_proxy().getChangelogEntries(
            self.name, '', '', '', '', dt_delta_str
        )
        self._logger.debug("Raw changelogs: {0}.".format(changelogs))
        for changelog in changelogs:
            if self.build["version"] in changelog["author"]:
                return changelog

    def _bug_id_fetcher(self, raw_bug_list):
        bug_id_pattern = re.compile(r"\d{7}")
        bug_id_list = re.findall(bug_id_pattern, raw_bug_list)
        self._logger.debug("Bug IDs in current build: {}.".format(bug_id_list))
        return set(bug_id_list)

    @property
    def bugs(self):
        """Return a set of bugs which are fixed in this build.

        {'1521092', '1506382', '1516644', '1514371', '1432288', '1501882',
         '1441965', '1508380', '1516680', '1525027'}
        """
        raw_bug_list = self.changelog["text"]
        self._logger.debug("Raw bug list {0}".format(raw_bug_list))
        return self._bug_id_fetcher(raw_bug_list)

    def download_url(self, task_id):
        """Retrun a URL for kernel download.

        Parameters of this method:
            task_id: ID of brew task which compiled this build
        """
        URL_prefix = "http://download.eng.bos.redhat.com/brewroot/work/"

        sub_tasks = self._get_proxy().getTaskChildren(task_id)
        self._logger.debug("Sub tasks {0}".format(sub_tasks))

        for sub_task in sub_tasks:
            if sub_task["arch"] == "x86_64":
                sub_task_id = str(sub_task["id"])
        self._logger.info("Found task ID {0}".format(sub_task_id))

        rpms = self._get_proxy().getTaskResult(sub_task_id)["rpms"]
        self._logger.debug("All build RPMS {0}".format(sub_tasks))

        for rpm in rpms:
            if self.name in rpm:
                URL_suffix = rpm
        self._logger.info("Found RPM {0}".format(URL_suffix))

        return URL_prefix + URL_suffix
