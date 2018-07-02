#!/usr/bin/env python
"""Parse result XML files and send report to owner."""

import re
from os import listdir
from os.path import isfile, join, basename, splitext
import argparse
import xml.etree.ElementTree as et
import smtplib
from email.message import EmailMessage
import hwlogging


def parse_xml(path, logger):
    """Parse JUnix XML files, list all failed cases."""
    hypervisors = {
        "2016-AUTO": "Windows Server 2016",
        "2012R2-AUTO": "Windows Server 2012R2",
        "2012-72-132": "Windows Server 2012",
        "10.73.196.97": "VMWare ESXi 6.7",
        "10.73.72.129": "VMWare ESXi 6.5",
        "10.73.196.236": "VMWare ESXi 6.0"
    }
    report_list = []

    files = [join(path, f) for f in listdir(path)
             if isfile(join(path, f)) and f.endswith(".xml")]
    logger.info("JUnit XML files: {0}.".format(files))

    for xml_file in files:
        file_meta = {}
        file_name = splitext(basename(xml_file))[0]
        file_info_list = file_name.split("-")[1:]
        file_meta["id"] = file_info_list[-1]
        file_meta["owner"] = file_info_list[-2]
        if "smoke" in file_info_list:
            file_meta["type"] = "smoke"
            hv_str = "-".join(file_info_list[:-3])
            if hv_str in hypervisors.keys():
                file_meta["hv"] = hypervisors[hv_str]
            else:
                file_meta["hv"] = hv_str
        else:
            file_meta["type"] = "functional"
            hv_str = "-".join(file_info_list[:-2])
            if hv_str in hypervisors.keys():
                file_meta["hv"] = hypervisors[hv_str]
            else:
                file_meta["hv"] = hv_str
            file_meta["hv"] = hv_str

        tree = et.parse(xml_file)
        root = tree.getroot()
        if root.tag == "testsuites":
            prefix = "testsuite/"
        else:
            prefix = ""
        for element in root.findall("./{0}properties/property".format(prefix)):
            if element.get("name") == "kernel.version":
                file_meta["kernel"] = element.get("value")
            if element.get("name") == "firmware.version":
                file_meta["firmware"] = element.get("value")

        file_meta["total"] = sum(1 for _ in root.iter("testcase"))
        # Get test case name from string like 'Test CDmount Failed.'
        failed = [x.text[5:-8] for x in root.findall(
            "./{0}testcase/failure".format(prefix)
        )]
        file_meta["total_failed"] = len(failed)
        file_meta["failed_cases"] = failed
        logger.info("Test Info: {0}".format(file_meta))

        report_list.append(file_meta)
    return report_list


def sender(metadata, logger, mail, smtp, task, hv):
    """Send report email to owner."""
    smoking = ""
    functional = ""
    i, j = (1, 1)
    for test in metadata:
        if test["total_failed"] == 0:
            result = "PASS"
        else:
            result = "FAIL"
        if test["type"] == "smoke":
            smoking += (
                '{5}: {6}\n'
                '    Platform: {0}\n    Firmware Type: {1}\n'
                '    Total Cases: {2}\n'
                '    Total Failed Cases: {3}\n    Failed Cases: {4}\n'
                ).format(
                    test["hv"], test["firmware"], test["total"],
                    test["total_failed"], ", ".join(test["failed_cases"]), i,
                    result
                )
            i += 1
        if test["type"] == "functional":
            functional += (
                '{5}: {6}\n'
                '    Platform: {0}\n    Firmware Type: {1}\n'
                '    Total Cases: {2}\n'
                '    Total Failed Cases: {3}\n    Failed Cases: {4}\n'
                ).format(
                    test["hv"], test["firmware"], test["total"],
                    test["total_failed"], ", ".join(test["failed_cases"]), j,
                    result
                )
            j += 1
    body = (
        'Hey {owner},\n\n'
        'Your brew task[1] compiled kernel {kernel_version} just triggered '
        '3rd automation test.\n\n'
        'Smoking Test Report:\n'
        '{smoking}\n'
        'Functional Test Report:\n'
        '{functional}\n'
        'If you need more help, feel free to contact us by sending email to '
        '3rd-qe-list@redhat.com. Thanks for using 3rd QE downstream '
        'kernel CI.\n\n'
        '[1] {task}{id}\n'
        '[2] Some of the failed cases might not be caused by your '
        'code change.\n\n\n'
        'Regards,\n'
        '3rd QE Team'
        ).format(
            owner=metadata[0]["owner"],
            id=metadata[0]["id"],
            kernel_version=metadata[0]["kernel"],
            smoking=smoking,
            functional=functional,
            task=task
        )
    logger.info(body)

    hv_str = {
        "1": "Hyper-V",
        "2": "ESXi",
        "3": "Hyper-V and ESXi"
    }

    msg = EmailMessage()
    msg['Subject'] = (
        '[3rd CI Report] {kernel_version} on {hv}').format(
            owner=metadata[0]["owner"],
            kernel_version=metadata[0]["kernel"],
            hv=hv_str[hv]
        )

    domain = re.search("@[\w.]+", mail)
    msg['From'] = mail
    msg['To'] = metadata[0]["owner"] + domain.group()
    msg['CC'] = mail
    msg.set_content(body)

    with smtplib.SMTP(smtp) as s:
        s.send_message(msg)


def main(args):
    """Programe mailbot starts from here."""
    # Print all avaliable arguments passed in.
    logger = hwlogging.Logger("mailbot.log", "./").logger
    logger.info("JUnit XML file path: {0}.".format(args.path))

    try:
        metadata = parse_xml(args.path, logger)
        sender(metadata, logger, args.mail, args.smtp, args.task, args.hv)
    # If bad things happened and no result xml file, it will not impact
    # docker container and volume clean task
    except IndexError:
        logger.info("Sending email fail.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Work with JUnit XML files.')
    parser.add_argument("--path", type=str, required=True,
                        help="path to store JUnit XML files")
    parser.add_argument("--mail", type=str, required=True,
                        help="email sent from")
    parser.add_argument("--smtp", type=str, required=True,
                        help="smtp server address")
    parser.add_argument("--task", type=str, required=True,
                        help="prefix of task URL")
    parser.add_argument("--hv", type=str, required=True,
                        help="hypervisor platform")
    args = parser.parse_args()

    main(args)
