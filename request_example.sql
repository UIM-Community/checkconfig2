CREATE VIEW IF NOT EXISTS
	't_bp2i_nimsoft_diffversion_count'
AS
SELECT
	RL.name as RobotName,RL.status,RL.os_minor,P.name,P.versions,P.build
FROM
	probes_list P
INNER JOIN
	robots_list RL ON RL.id = P.robotid
WHERE
	(P.name = 'cdm' AND ( P.versions NOT LIKE '%5.40HF3MET06%' OR P.build != 4 ) ) OR
	(P.name = 'ntevl' AND (P.versions != '4.22-HF1' OR P.build != 1) ) OR
	(P.name = 'logmon' AND (P.versions != '3.55' OR P.build != 5 ) ) OR
	(P.name = 'dirscan' AND (P.versions != '3.14' OR P.build != 18 ) ) OR
	(P.name = 'ntservices' AND (P.versions != '3.24HF' OR P.build != 2) ) OR
	(P.name = 'ntperf' AND (P.versions != '1.89' OR P.build != 24 ) ) OR
	(P.name = 'processes' AND ( P.versions != '4.31-HF' OR P.build != 271 ) )


SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'ntperf64'
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'ntperf' AND (P.versions != '1.89' OR P.build != 24)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'ntevl' AND (P.versions != '4.22-HF1' OR P.build != 2)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'ntservices' AND (P.versions != '3.24HF' OR P.build != 2)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'logmon' AND (P.versions != '3.55' OR P.build != 5)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'dirscan' AND (P.versions != '3.14' OR P.build != 18)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'processes' AND (P.versions != '4.31' OR P.build != 227)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'cdm' AND (P.versions != '5.40HF3MET06' OR P.build != 4)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'controller' AND (P.versions != '7.80HF13' OR P.build != 3670)
SELECT RL.name,RL.status,RL.os_minor,P.name,P.versions,P.build FROM probes_list P INNER JOIN robots_list RL ON RL.id = P.robotid WHERE P.name = 'snmpget'

SELECT * FROM robots_list WHERE ip = '127.0.0.1' OR ip LIKE '%166.254%'
SELECT * FROM robots_list WHERE status = 2

SELECT
	RL.os_major,
	NM.robotname,
	NM.probeName
FROM
	t_bp2i_nimsoft_missingprobes AS NM
INNER JOIN robots_list RL ON NM.robotname = RL.name
WHERE
	NM.probeName IN (
		'ntperf',
		'ntevl',
		'ntservices'
	)
AND RL.os_minor NOT IN ('Linux','AIX')
ORDER BY
	NM.probeName


SELECT
	RL.name AS RobotName,RL.os_minor,P.name AS ProbeName,P.versions,P.build,C.profile
FROM
	probes_config C
INNER JOIN
	probes_list P ON P.id = C.probeid
INNER JOIN
	robots_list RL ON RL.id = P.robotid
WHERE C.profile = 'security'
