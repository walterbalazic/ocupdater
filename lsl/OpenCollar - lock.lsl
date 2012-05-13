//OpenCollar - lock
//Licensed under the GPLv2, with the additional requirement that these scripts remain "full perms" in Second Life.  See "OpenCollar License" for details.

list g_lOwners;

string g_sParentMenu = "Main";

string g_sRequestType; //may be "owner" or "secowner" or "rem secowner"
key g_kHTTPID;

integer g_iListenChan = 802930;//just something i randomly chose
integer g_iListener;

integer g_iLocked = FALSE;
key g_kLockedBy;
string g_sLockedBy;

string g_sOpenLockPrimName="OpenLock"; // Prim description of elements that should be shown when unlocked
string g_sClosedLockPrimName="ClosedLock"; // Prim description of elements that should be shown when locked
list g_lClosedLockElements; //to store the locks prim to hide or show //EB
list g_lOpenLockElements; //to store the locks prim to hide or show //EB

string LOCK = "*Lock*";
string UNLOCK = "*Unlock*";

//MESSAGE MAP
integer LM_TOAUTH_NEW = 532;
integer LM_AUTHED_PRIMARY = 514;
integer LM_AUTHED_SECONDARY = 516;
integer LM_AUTHED_GUEST = 518;
integer LM_AUTHED_DENIED = 526;
integer LM_CHANGED_AUTH = 576;
integer LM_DO_SAFEWORD = 599;  // new for safeword

//integer SEND_IM = 1000; deprecated.  each script should send its own IMs now.  This is to reduce even the tiny bt of lag caused by having IM slave scripts
integer POPUP_HELP = 1001;

integer LM_SETTING_SAVE = 2000;//scripts send messages on this channel to have settings saved to httpdb
//str must be in form of "token=value"
integer LM_SETTING_REQUEST = 2001;//when startup, scripts send requests for settings on this channel
integer LM_SETTING_RESPONSE = 2002;//the httpdb script will send responses on this channel
integer LM_SETTING_DELETE = 2003;//delete token from DB
integer LM_SETTING_EMPTY = 2004;//sent by httpdb script when a token has no value in the db


integer MENUNAME_REQUEST = 3000;
integer MENUNAME_RESPONSE = 3001;
integer MENUNAME_REMOVE = 3003;

integer RLV_CMD = 6000;
integer RLV_REFRESH = 6001;//RLV plugins should reinstate their restrictions upon receiving this message.
integer RLV_CLEAR = 6002;//RLV plugins should clear their restriction lists upon receiving this message.

//added to prevent altime attach messages
integer g_bDetached = FALSE;

key g_kWearer;

Notify(key kID, string sMsg, integer iAlsoNotifyWearer)
{
    if (kID == g_kWearer)
    {
        llOwnerSay(sMsg);
    }
    else
    {
        llInstantMessage(kID,sMsg);
        if (iAlsoNotifyWearer)
        {
            llOwnerSay(sMsg);
        }
    }
}

NotifyOwners(string sMsg)
{
    integer n;
    integer stop = llGetListLength(g_lOwners);
    for (n = 0; n < stop; n += 2)
    {
        // Cleo: Stop IMs going wild
        if (g_kWearer != llGetOwner())
        {
            llResetScript();
            return;
        }
        else
            Notify((key)llList2String(g_lOwners, n), sMsg, FALSE);
    }
}

string GetPSTDate()
{ //Convert the date from UTC to PST if GMT time is less than 8 hours after midnight (and therefore tomorow's date).
    string DateUTC = llGetDate();
    if (llGetGMTclock() < 28800) // that's 28800 seconds, a.k.a. 8 hours.
    {
        list DateList = llParseString2List(DateUTC, ["-", "-"], []);
        integer year = llList2Integer(DateList, 0);
        integer month = llList2Integer(DateList, 1);
        integer day = llList2Integer(DateList, 2);
        day = day - 1;
        return (string)year + "-" + (string)month + "-" + (string)day;
    }
    return llGetDate();
}

string GetTimestamp() // Return a string of the date and time
{
    integer t = (integer)llGetWallclock(); // seconds since midnight

    return GetPSTDate() + " " + (string)(t / 3600) + ":" + PadNum((t % 3600) / 60) + ":" + PadNum(t % 60);
}

string PadNum(integer value)
{
    if(value < 10)
    {
        return "0" + (string)value;
    }
    return (string)value;
}

BuildLockElementList()//EB
{
    integer n;
    integer iLinkCount = llGetNumberOfPrims();
    list lParams;

    // clear list just in case
    g_lOpenLockElements = [];
    g_lClosedLockElements = [];

    //root prim is 1, so start at 2
    for (n = 2; n <= iLinkCount; n++)
    {
        // read description
        lParams=llParseString2List((string)llGetObjectDetails(llGetLinkKey(n), [OBJECT_DESC]), ["~"], []);
        // check if name is lock name
        if (llList2String(lParams, 0)==g_sClosedLockPrimName)
        {
            // if so store the number of the prim
            g_lClosedLockElements += [n];
            //llOwnerSay("added " + (string)n + " to celements:  "+ llList2String(llGetObjectDetails(llGetLinkKey(n), [OBJECT_NAME]),0));
        }
        else if (llList2String(lParams, 0)==g_sOpenLockPrimName) 
        {
            // if so store the number of the prim
            g_lOpenLockElements += [n];
            //llOwnerSay("added " + (string)n + " to oelements: "+ llList2String(llGetObjectDetails(llGetLinkKey(n), [OBJECT_NAME]),0));
        }
    }
}

SetLockElementAlpha() //EB
{
    //loop through stored links, setting alpha if element type is lock
    integer n;
    float fAlpha;
    if (g_iLocked) fAlpha = 1.0; else fAlpha = 0.0;
    integer iLinkElements = llGetListLength(g_lOpenLockElements);
    for (n = 0; n < iLinkElements; n++)
    {
        llSetLinkAlpha(llList2Integer(g_lOpenLockElements,n), 1.0 - fAlpha, ALL_SIDES);
    }
    iLinkElements = llGetListLength(g_lClosedLockElements);
    for (n = 0; n < iLinkElements; n++)
    {
        llSetLinkAlpha(llList2Integer(g_lClosedLockElements,n), fAlpha, ALL_SIDES);
    }
}

Lock(key kID, integer iNum)
{
    if (iNum > LM_AUTHED_SECONDARY && kID != g_kWearer)
        Notify(kID, "Sorry, only owners and wearer can lock the collar.", FALSE);
    else if (g_iLocked > 0 && kID == g_kWearer && g_kLockedBy != g_kWearer)
        Notify(kID, "It's already locked by somebody else, and you cannot claim the key.", FALSE);
    else
    {
        g_iLocked = iNum;
        g_kLockedBy = kID;
        g_sLockedBy = llGetUsername(kID);
        llMessageLinked(LINK_SET, LM_SETTING_SAVE, "locked="+(string)iNum+","+(string)kID+","+g_sLockedBy, NULL_KEY);
        llMessageLinked(LINK_SET, RLV_CMD, "detach=n", NULL_KEY);
        llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + UNLOCK, NULL_KEY);
        llPlaySound("abdb1eaa-6160-b056-96d8-94f548a14dda", 1.0);
        llMessageLinked(LINK_SET, MENUNAME_REMOVE, g_sParentMenu + "|" + LOCK, NULL_KEY);
        SetLockElementAlpha();//EB
        Notify(kID, "Locked.", FALSE);
        if (kID!=g_kWearer) llOwnerSay("Your collar has been locked by "+g_sLockedBy+".");
    }
}

Unlock(key kID, integer iNum)
{
    if (iNum > LM_AUTHED_SECONDARY)
        Notify(kID, "Sorry, only owners can unlock the collar.", FALSE);
    else if (iNum > g_iLocked)
        Notify(kID, "Sorry, somebody with greater autority than you owns the lock.", FALSE);
    else if (kID == g_kWearer && g_kLockedBy != g_kWearer)
        Notify(kID, "The collar already locked by somebody else, and you cannot claim the key.", FALSE);
    else 
    {  //primary owners can lock and unlock. no one else
        g_iLocked = FALSE;
        llMessageLinked(LINK_SET, LM_SETTING_DELETE, "locked", NULL_KEY);
        llMessageLinked(LINK_SET, RLV_CMD, "detach=y", NULL_KEY);
        llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + LOCK, NULL_KEY);
        llPlaySound("ee94315e-f69b-c753-629c-97bd865b7094", 1.0);
        llMessageLinked(LINK_SET, MENUNAME_REMOVE, g_sParentMenu + "|" + UNLOCK, NULL_KEY);
        SetLockElementAlpha(); //EB
        Notify(kID, "Unlocked.", FALSE);
        if (kID!=g_kWearer) llOwnerSay("Your collar has been unlocked.");
    }
}



default
{
    state_entry()
    {   //until set otherwise, wearer is owner
        g_kWearer = llGetOwner();
        //        g_lOwnersName = llKey2Name(llGetOwner());   //NEVER used
        g_iListenChan = -1 - llRound(llFrand(9999999.0));
        //no more needed
        //        llSleep(1.0);//giving time for others to reset before populating menu
        //        llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + LOCK, NULL_KEY);
        
        BuildLockElementList();//EB
        SetLockElementAlpha(); //EB

    }

    link_message(integer iSender, integer iNum, string sStr, key kID)
    {
        if (iNum >= LM_AUTHED_PRIMARY && iNum < LM_AUTHED_DENIED)
        {
            if (sStr == "settings")
            {
                if (g_iLocked) Notify(kID, "Locked by "+g_sLockedBy+".", FALSE);
                else Notify(kID, "Unlocked.", FALSE);
            }
            else if (sStr == "lock" || (!g_iLocked && sStr == "togglelock"))
            {
                Lock(kID, iNum);
            }
            else if (sStr == "unlock" || (g_iLocked && sStr == "togglelock"))
            {
                Unlock(kID, iNum);
            }
            
            else if (sStr == "menu " + LOCK)
            {
                Lock(kID, iNum);
                llMessageLinked(LINK_SET, iNum, "menu " + g_sParentMenu, kID);
            }
            else if (sStr == "menu " + UNLOCK)
            {
                Unlock(kID, iNum);
                llMessageLinked(LINK_SET, iNum, "menu " + g_sParentMenu, kID);
            }
        }
        else if (iNum == LM_SETTING_RESPONSE)
        {
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if (sToken == "locked")
            {
                list lLocked = llParseString2List(sValue, [","], []);
                g_iLocked = llList2Integer(lLocked, 0);
                g_kLockedBy = llList2Key(lLocked, 1);
                g_sLockedBy = llList2String(lLocked, 2);
                if (g_iLocked)
                {
                    llMessageLinked(LINK_SET, RLV_CMD, "detach=n", NULL_KEY);
                    llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + UNLOCK, NULL_KEY);
                    llMessageLinked(LINK_SET, MENUNAME_REMOVE, g_sParentMenu + "|" + LOCK, NULL_KEY);
                }
                else
                {
                    llMessageLinked(LINK_SET, RLV_CMD, "detach=y", NULL_KEY);
                    llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + LOCK, NULL_KEY);
                    llMessageLinked(LINK_SET, MENUNAME_REMOVE, g_sParentMenu + "|" + UNLOCK, NULL_KEY);
                }
                SetLockElementAlpha(); //EB

            }
            else if (sToken == "owner")
            {
                g_lOwners = llParseString2List(sValue, [","], []);
            }
        }
        else if (iNum == LM_SETTING_SAVE)
        {
            list lParams = llParseString2List(sStr, ["="], []);
            string sToken = llList2String(lParams, 0);
            string sValue = llList2String(lParams, 1);
            if (sToken == "owner")
            {
                g_lOwners = llParseString2List(sValue, [","], []);
            }
        }
        else if (iNum == MENUNAME_REQUEST && sStr == g_sParentMenu)
        {
            if (g_iLocked)
            {
                llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + UNLOCK, NULL_KEY);
            }
            else
            {
                llMessageLinked(LINK_SET, MENUNAME_RESPONSE, g_sParentMenu + "|" + LOCK, NULL_KEY);
            }
        }
        else if (iNum == RLV_REFRESH)
        {
            if (g_iLocked)
            {
                llMessageLinked(LINK_SET, RLV_CMD, "detach=n", NULL_KEY);
            }
            else
            {
                llMessageLinked(LINK_SET, RLV_CMD, "detach=y", NULL_KEY);
            }
        }
        else if (iNum == RLV_CLEAR)
        {
            if (g_iLocked)
            {
                llMessageLinked(LINK_SET, RLV_CMD, "detach=n", NULL_KEY);
            }
            else
            {
                llMessageLinked(LINK_SET, RLV_CMD, "detach=y", NULL_KEY);
            }
        }
        else if (iNum == LM_CHANGED_AUTH)
        {
            if (kID == g_kLockedBy && (integer)sStr > LM_AUTHED_SECONDARY) Unlock(kID, LM_AUTHED_PRIMARY);
        }
    }
    attach(key kID)
    {
        if (g_iLocked)
        {
            if(kID == NULL_KEY)
            {
                g_bDetached = TRUE;
                NotifyOwners(llKey2Name(g_kWearer) + " has detached me while locked at " + GetTimestamp() + "!");
            }
            else if(g_bDetached)
            {
                NotifyOwners(llKey2Name(g_kWearer) + " has re-atached me at " + GetTimestamp() + "!");
                g_bDetached = FALSE;
            }
        }
    }

    changed(integer iChange)
    {
        if (iChange & CHANGED_OWNER)
        {
            llResetScript();
        }
    }

    on_rez(integer start_param)
    {
        // stop IMs going wild
        if (g_kWearer != llGetOwner())
        {
            llResetScript();
        }
    }

}