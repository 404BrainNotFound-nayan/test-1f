DECLARE @RunDate DATE = CAST(GETDATE() AS DATE);
-- NOTE: GETDATE() uses the SQL Server's own local time zone, not IST specifically.
-- If this server runs in UTC (common on cloud-hosted SQL Server), running at 5 AM IST
-- will actually land on the PREVIOUS UTC day, shifting this whole date window back by one day.
-- Run: SELECT GETDATE(), SYSUTCDATETIME();  -- if they're within a few minutes of each other, server = UTC.
-- If server = UTC, replace the line above with:
-- DECLARE @RunDate DATE = CAST(SYSUTCDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'India Standard Time' AS DATE);


;WITH OrgEmailMap AS (
    -- one row per client: OrgID, To email, CC email
    SELECT * FROM (VALUES
        (15864, 'Suruchi.Goraksha@edelman.com', 'Vinayak.Amballa@edelman.com; bookings@in.musafir.com'),
        (15863, 'Suruchi.Goraksha@edelman.com', 'Vinayak.Amballa@edelman.com; bookings@in.musafir.com'),
        (14695, 'Suruchi.Goraksha@edelman.com', 'Vinayak.Amballa@edelman.com; bookings@in.musafir.com'),
        (16348, 'kp@arohi.com', 'bookings@in.musafir.com'),
        (16330, 'kp@arohi.com', 'bookings@in.musafir.com'),
        (16331, 'kp@arohi.com', 'bookings@in.musafir.com'),
        (17303, 'kailas.sondge@cohizon.com', 'bookings@in.musafir.com'),
        (15739, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15738, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15737, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15736, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15735, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15734, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15731, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15730, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com'),
        (15729, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com')
        ----(14688, 'vishal.doke@cryopdp.com', 'bookings@in.musafir.com')
    ) AS M (OrgID, ToEmail, CCEmail)
)

/* ---------------- Part 1 : Booking ---------------- */
SELECT DISTINCT
    BookingFile.MarketProfileID                         as [Market]
	,BookingFile.SystemReference                       AS [Trip ID],
    [Booking].ID                                      AS [ID],
    Organization.ID                                   AS [Organization ID],
    UPPER(Organization.[Name])                        AS [Client name],
    OrgEmailMap.ToEmail                               AS [To - Email id],
    OrgEmailMap.CCEmail                               AS [CC email id],

    F.TravelDate                                      AS [Travel date],
    CAST(AirSegment.Departure AS DATE)                AS [Travel date sort],
    Booking.ProviderReference                         AS [PNR],

    /* ---- Flight Details split into separate columns ---- */
    Airline.IATACode                                  AS [Airline],
    AirSegment.FlightNumber                           AS [Flight Number],
    F.Sector                                          AS [Sector],
    F.DepTime                                         AS [Departure Time],
    F.ArrTime                                         AS [Arrival Time],
    Anc.Seats                                         AS [Seat],
    Anc.Meal                                          AS [Meal],

    UPPER(Traveler.FullName)                          AS [Pax Name],
	CASE WHEN CHARINDEX(' ', LTRIM(RTRIM(Traveler.FullName))) = 0
     THEN UPPER(LTRIM(RTRIM(Traveler.FullName)))
     ELSE UPPER(RIGHT(LTRIM(RTRIM(Traveler.FullName)),
          CHARINDEX(' ', REVERSE(LTRIM(RTRIM(Traveler.FullName)))) - 1))
END AS [Last Name],

    CASE 
        WHEN TravelerProfile.ContactNumber IS NOT NULL 
             AND LTRIM(RTRIM(TravelerProfile.ContactNumber)) <> ''
        THEN TravelerProfile.ContactNumber
        ELSE BookingFile.ContactNumber
    END                                                AS [Contact Number - Final],
	F.BoardingPassDate                                AS [Boarding pass date]

FROM BookingFile
    JOIN Booking      WITH (READPAST) ON Booking.BookingFileID = BookingFile.ID
    JOIN Organization WITH (READPAST) ON Organization.ID = BookingFile.BookedForOrganizationID
    JOIN OrgEmailMap                  ON OrgEmailMap.OrgID = Organization.ID
    JOIN AirOriginDestination WITH (READPAST) ON AirOriginDestination.BookingID = Booking.ID
    JOIN AirSegment   WITH (READPAST) ON AirSegment.AirOriginDestinationID = AirOriginDestination.ID
    JOIN Airport A1   WITH (READPAST) ON A1.ID = AirSegment.DepartureAirportID
    JOIN Airport A2   WITH (READPAST) ON A2.ID = AirSegment.ArrivalAirportID
    LEFT JOIN Airline WITH (READPAST) ON Airline.ID = Booking.ValidatingAirlineID
    JOIN AirTraveler  WITH (READPAST) ON AirTraveler.BookingID = Booking.ID
    JOIN Traveler     WITH (READPAST) ON Traveler.ID = AirTraveler.TravelerID
	LEFT JOIN TravelerProfile WITH (READPAST) ON TravelerProfile.ID = Traveler.TravelerProfileID

    -- flight values, calculated once
    CROSS APPLY (SELECT
        UPPER(FORMAT(AirSegment.Departure, 'ddMMMyyyy'))              AS TravelDate,
        CONCAT(A1.IATACode, '-', A2.IATACode)                         AS Sector,
        FORMAT(AirSegment.Departure, 'HHmm')                          AS DepTime,
        FORMAT(AirSegment.Arrival,  'HHmm')                           AS ArrTime,
        UPPER(FORMAT(DATEADD(DAY, -2, AirSegment.Departure),'ddMMM')) AS BoardingPassDate
    ) AS F

    -- meal + seat of THIS traveler
    OUTER APPLY (SELECT
        AirTraveler.AncillaryDetails.value(
            '(/ArrayOfAirAncillaryInfo/AirAncillaryInfo[AncillaryType="Meal"]/NameEN)[1]',
            'VARCHAR(200)')                                           AS Meal,
        (SELECT STRING_AGG(
                    CONCAT(S.N.value('(SeatNumber)[1]',  'VARCHAR(10)'), ' ',
                           S.N.value('(SeatLocation)[1]','VARCHAR(20)')),
                    ', ')
         FROM AirTraveler.AncillaryDetails.nodes(
                '/ArrayOfAirAncillaryInfo/AirAncillaryInfo[AncillaryType="Seat"]') AS S(N)
        )                                                             AS Seats
    ) AS Anc

WHERE
    Booking.TravelSectorID = 1                          -- flights only
    AND Booking.IsActive = 1
    AND Booking.BookingStatusID IN (16)                 -- ticketed
    AND [Booking].AmountNetRemit > 1

    -- future trips only: excludes today, no upper bound
    AND CAST(AirSegment.Departure AS DATE) > @RunDate

UNION

/* ---------------- Part 2 : Service ---------------- */
SELECT DISTINCT
     BookingFile.MarketProfileID                         as [Market]
	,BookingFile.SystemReference                       AS [Trip ID],
    [Service].ID                                      AS [ID],
    Organization.ID                                   AS [Organization ID],
    UPPER(Organization.[Name])                        AS [Client name],
    OrgEmailMap.ToEmail                               AS [To - Email id],
    OrgEmailMap.CCEmail                               AS [CC email id],

    COALESCE(UPPER(FORMAT(Seg.SegDate,'ddMMMyyyy')),
             UPPER(FORMAT(F.TravelDate,'ddMMMyyyy')))    AS [Travel date],
    COALESCE(Seg.SegDate, F.TravelDate)               AS [Travel date sort],
    [Service].ProviderReference                       AS [PNR],

    /* ---- Flight Details split into separate columns ----
       Falls back to the service name (SN) when the GDS line
       could not be parsed; Seat/Meal not available on Service. */
    COALESCE(Seg.Carrier, F.FlightName)               AS [Airline],
    Seg.FlightNo                                      AS [Flight Number],
    COALESCE(Seg.Sector, NULLIF(F.Sector, ''))        AS [Sector],
    Seg.DepTime                                       AS [Departure Time],
    Seg.ArrTime                                       AS [Arrival Time],
    CAST(NULL AS VARCHAR(200))                        AS [Seat],
    CAST(NULL AS VARCHAR(200))                        AS [Meal],

    UPPER(Traveler.FullName)                          AS [Pax Name],
	CASE WHEN CHARINDEX(' ', LTRIM(RTRIM(Traveler.FullName))) = 0
     THEN UPPER(LTRIM(RTRIM(Traveler.FullName)))
     ELSE UPPER(RIGHT(LTRIM(RTRIM(Traveler.FullName)),
          CHARINDEX(' ', REVERSE(LTRIM(RTRIM(Traveler.FullName)))) - 1))
END AS [Last Name],

    CASE 
        WHEN TravelerProfile.ContactNumber IS NOT NULL 
             AND LTRIM(RTRIM(TravelerProfile.ContactNumber)) <> ''
        THEN TravelerProfile.ContactNumber
        ELSE BookingFile.ContactNumber
    END                                                AS [Contact Number - Final],
	UPPER(FORMAT(DATEADD(DAY, -2,
          COALESCE(Seg.SegDate, F.TravelDate)),'ddMMM'))
                                                      AS [Boarding pass date]

FROM BookingFile
    JOIN [Service]    WITH (READPAST) ON [Service].BookingFileID = BookingFile.ID
    JOIN Organization WITH (READPAST) ON Organization.ID = BookingFile.BookedForOrganizationID
    JOIN OrgEmailMap                  ON OrgEmailMap.OrgID = Organization.ID
    LEFT JOIN ServiceTraveler WITH (READPAST) ON ServiceTraveler.ServiceID = [Service].ID
    LEFT JOIN Traveler        WITH (READPAST) ON Traveler.ID = ServiceTraveler.TravelerID
	LEFT JOIN TravelerProfile WITH (READPAST) ON TravelerProfile.ID = Traveler.TravelerProfileID

    -- step 1: basic values from the XML (read once)
    CROSS APPLY (SELECT
        TRY_CONVERT(DATE,
            [Service].Details.value('(/ServiceDetailsInfo/IL/@SD)[1]','VARCHAR(20)')) AS TravelDate,
        COALESCE(
            [Service].Details.value('(/ServiceDetailsInfo/IL/@LOC)[1]','VARCHAR(50)'), '') AS Sector,
        TRIM(
            [Service].Details.value('(/ServiceDetailsInfo/SN)[1]','VARCHAR(200)'))    AS FlightName,
        [Service].Details.value('(/ServiceDetailsInfo/@II)[1]','VARCHAR(MAX)')        AS IIText
    ) AS F

    -- step 2: split II into lines; keep only flight lines (contain " HK")
    OUTER APPLY (SELECT LTRIM(RTRIM(L.value)) AS SegLine
                 FROM STRING_SPLIT(REPLACE(COALESCE(F.IIText,''), CHAR(13), ''), CHAR(10)) AS L
                 WHERE L.value LIKE '% HK%'
    ) AS SegLines

    -- step 3: squeeze spaces, turn the line into a list of words
    OUTER APPLY (SELECT
        CASE WHEN SegLines.SegLine IS NULL THEN NULL ELSE
            '["' + REPLACE(STRING_ESCAPE(
                     REPLACE(REPLACE(REPLACE(SegLines.SegLine,' ','<>'),'><',''),'<>',' ')
                   ,'json'), ' ', '","') + '"]'
        END AS Words
    ) AS T


    OUTER APPLY (SELECT
        JSON_VALUE(T.Words,'$[1]')                                        AS Carrier,
        JSON_VALUE(T.Words,'$[2]')                                        AS FlightNo,
        JSON_VALUE(T.Words,'$[4]')                                        AS DateTxt,
        CONCAT(LEFT(JSON_VALUE(T.Words,'$[6]'),3), '-',
               SUBSTRING(JSON_VALUE(T.Words,'$[6]'),4,3))                 AS Sector,
        JSON_VALUE(T.Words,'$[8]')                                        AS DepTime,
        JSON_VALUE(T.Words,'$[9]')                                        AS ArrTime,
        -- real date = "31AUG" + year of trip start; roll to next year if needed
        CASE WHEN TRY_CONVERT(DATE,
                  CONCAT(STUFF(JSON_VALUE(T.Words,'$[4]'),3,0,' '), ' ',
                         YEAR(F.TravelDate))) < F.TravelDate
             THEN DATEADD(YEAR, 1, TRY_CONVERT(DATE,
                  CONCAT(STUFF(JSON_VALUE(T.Words,'$[4]'),3,0,' '), ' ',
                         YEAR(F.TravelDate))))
             ELSE TRY_CONVERT(DATE,
                  CONCAT(STUFF(JSON_VALUE(T.Words,'$[4]'),3,0,' '), ' ',
                         YEAR(F.TravelDate)))
        END                                                               AS SegDate
    ) AS Seg

WHERE
    [Service].ServiceTypeID IN (13,15,49,50)   -- flight services
    AND [Service].IsActive = 1
    AND [Service].BookingStatusID = 16
    -- future trips only: excludes today, no upper bound
    AND COALESCE(Seg.SegDate, F.TravelDate) > @RunDate
    AND [Service].AmountNetRemit > 1

ORDER BY [Travel date sort] ASC, [Organization ID], [PNR];



