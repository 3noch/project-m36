function appendResult(title, result)
{
    //prepend the page with an additional relation result
    var sheet = document.getElementById("sheet");
    var template = document.getElementById("sectiontemplate").cloneNode(true);
    template.removeAttribute("id");
    var titleSpan = document.createElement("span");
    titleSpan.textContent = title;
    template.getElementsByClassName("title")[0].appendChild(titleSpan);
    template.getElementsByClassName("result")[0].appendChild(result);
    if(result.nodeName == "TABLE") // show some relation statistics
    {
	var tupleCount = result.querySelectorAll(".result > table > tbody > tr").length
	var attrCount = result.querySelectorAll(".result > table > thead > tr > th").length
	var attrText = attrCount + " attribute" + (attrCount == 1 ? "" : "s")
	var tupleText = tupleCount + " tuple" + (tupleCount == 1 ? "" : "s")
	template.getElementsByClassName("relinfo")[0].textContent = attrText + ", " + tupleText;
    }
    var interactor = document.getElementById("interactor");
    sheet.insertBefore(template, interactor);
    window.scrollTo(0,document.body.scrollHeight);
}

function updateStatus(status)
{
    var tutd = document.getElementById("tutd").value;
    if(status.relation)
    {
	var relastable = conn.generateRelation(status.relation);
	appendResult(tutd, relastable);
	mungeEmptyRows();
    }
    if(status.acknowledgement)
    {
	var ok = document.createElement("span");
	ok.textContent="OK";
	appendResult(tutd, ok);
    }
    if(status.error)
    {
	var error = document.createElement("span");
	error.textContent=status.error;
	appendResult(tutd, error);
    }
}

var conn;

function connectOrDisconnect(form)
{
    var formin = form.elements;
    var host = formin["host"].value;
    var port = formin["port"].value;
    var dbname = formin["dbname"].value;
    
    if(window.conn && window.conn.readyState() == 1)
    {
	//disconnect
	window.conn.close();
	toggleConnectionFields(form, true, "Connect");
    }
    else
    {
	//connect
	window.conn = new ProjectM36Connection(host, port, dbname,
					       connectionOpened,
					       connectionError,
					       updateStatus,
					       connectionClosed);
	toggleConnectionFields(form, false, "Connecting...");
    }
    return false;
}

function connectionError(event)
{
    var err = document.createElement("span");
    err.textContent = "Failed to connect to websocket server. Please check the connection parameters and try again.";
    appendResult("Connect", err);
    connectionClosed(event)
}

function connectionClosed(event)
{
    toggleConnectionFields(document.getElementById("connection"), true, "Connect");
}

function toggleConnectionFields(form, enabled, status)
{
    form.elements["connect"].value = status;
    var readonlyElements = [form.elements["host"], form.elements["port"], form.elements["dbname"]];
    for(var ein=0; ein < readonlyElements.length; ein++)
    {
	var e = readonlyElements[ein];
	if(enabled)
	{
	    e.removeAttribute("readonly");
	}
	else
	{
	    e.setAttribute("readonly", "readonly");
	}
    }
}

function connectionOpened(event)
{
    toggleConnectionFields(document.getElementById("connection"), false, "Disconnect");
}

function execTutorialD()
{
    var tutd = document.getElementById("tutd").value;
    if(!window.conn || window.conn.readyState() != 1)
    {
	var err = document.createElement("span");
	err.textContent = "Cannot execute command until a database connection is established.";
	appendResult(tutd, err);
    }
    else
    {
	conn.executeTutorialD(tutd);
    }
    return false;
}

function hideParent(element)
{
    var deleteNode = element.parentNode;
    element.parentNode.parentNode.removeChild(deleteNode)
}

function toggleSamples(element,show)
{
    var samples = document.getElementById("samples");
    if(show)
    {
	samples.style.display = "block";
    }
    else
    {
	samples.style.display = "none";
    }
}

function installSampleHandlers()
{
    var samples = document.querySelectorAll("#samples li");
    for(var idx = 0; idx < samples.length; idx++)
    {
	var tutd = document.getElementById("tutd");
	var el = samples[idx];
	el.onclick = function(el) { 
	    tutd.value = el.target.textContent; 
	}
    }
}