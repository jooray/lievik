CrewAI is designed for orchestrating, autonomous AI agents that collaborate to achieve complex goals. It simplifies the development of multi-agent systems by allowing you to define agents with specific roles, goals, and backstories, and then assign tasks to them. This example demonstrates how to build a multi-agent system for a Chief Operating Officer (COO) use case: analyzing customer support data to identify issues and propose process improvements using Gemini 2.5 Pro.

The goal is to create a "crew" of AI agents that can:

    Fetch and analyze customer support data (simulated in this example).
    Identify recurring problems and process bottlenecks.
    Suggest actionable improvements.
    Compile the findings into a concise report suitable for a COO.

If you don't have a Gemini API Key yet, you can get one for free in the Google AI Studio.

 pip install "crewai[tools]"

Set your Gemini API key as an environment variable named GEMINI_API_KEY. Configure CrewAI to use the Gemini 2.5 Pro model.

import os
from crewai import LLM

# Read your API key from the environment variable
gemini_api_key = os.getenv("GEMINI_API_KEY")

if not gemini_api_key:
    raise ValueError("GEMINI_API_KEY environment variable not set.")

# Use Gemini 2.5 Pro Experimental model
gemini_llm = LLM(
    model='gemini/gemini-2.5-pro-preview-05-06', 
    api_key=gemini_api_key,
    temperature=0.0 # Lower temperature for more factual analysis
)

Defining Components

CrewAI applications are built using several key components: Tools, Agents, Tasks, and the Crew itself.
Tools

Tools are capabilities that agents can use to interact with the outside world or perform specific actions. Here, we define a placeholder tool to simulate fetching customer support data. In a real application, this could connect to a database, API, or file system.

from crewai.tools import BaseTool

# Placeholder Tool for fetching customer support data
class CustomerSupportDataTool(BaseTool):
    name: str = "Customer Support Data Fetcher"
    description: str = "Fetches recent customer support interactions, tickets, and feedback. Returns a summary string."

    def _run(self, argument: str) -> str:
        # In a real scenario, this would query a database or API.
        # For this example, we return simulated data.
        print(f"--- Fetching data for query: {argument} ---")
        return (
            """Recent Support Data Summary:
- 50 tickets related to 'login issues'. High resolution time (avg 48h).
- 30 tickets about 'billing discrepancies'. Mostly resolved within 12h.
- 20 tickets on 'feature requests'. Often closed without resolution.
- Frequent feedback mentions 'confusing user interface' for password reset.
- High volume of calls related to 'account verification process'.
- Sentiment analysis shows growing frustration with 'login issues' resolution time.
- Support agent notes indicate difficulty reproducing 'login issues'."""
        )

support_data_tool = CustomerSupportDataTool()

Agents

Agents are the individual AI workers in your crew. Each agent has a specific role, goal, backstory, assigned llm, and potentially tools.

from crewai import Agent

# Agent 1: Data Analyst
data_analyst = Agent(
    role='Customer Support Data Analyst',
    goal='Analyze customer support data to identify trends, recurring issues, and key pain points.',
    backstory=(
        """You are an expert data analyst specializing in customer support operations. 
        Your strength lies in identifying patterns and quantifying problems from raw support data."""
    ),
    verbose=True,
    allow_delegation=False, # This agent focuses on its specific task
    tools=[support_data_tool], # Assign the data fetching tool
    llm=gemini_llm # Use the configured Gemini LLM
)

# Agent 2: Process Optimizer
process_optimizer = Agent(
    role='Process Optimization Specialist',
    goal='Identify bottlenecks and inefficiencies in current support processes based on the data analysis. Propose actionable improvements.',
    backstory=(
        """You are a specialist in optimizing business processes, particularly in customer support. 
        You excel at pinpointing root causes of delays and inefficiencies and suggesting concrete solutions."""
    ),
    verbose=True,
    allow_delegation=False,
    # No specific tools needed, relies on the analysis context provided by the data_analyst
    llm=gemini_llm
)

# Agent 3: Report Writer
report_writer = Agent(
    role='Executive Report Writer',
    goal='Compile the analysis and improvement suggestions into a concise, clear, and actionable report for the COO.',
    backstory=(
        """You are a skilled writer adept at creating executive summaries and reports. 
        You focus on clarity, conciseness, and highlighting the most critical information and recommendations for senior leadership."""
    ),
    verbose=True,
    allow_delegation=False,
    llm=gemini_llm
)

Tasks

Tasks define the specific assignments for the agents. Each task has a description, expected_output, and is assigned to an agent. Tasks can depend on the output of previous tasks.

from crewai import Task

# Task 1: Analyze Data
analysis_task = Task(
    description=(
        """Fetch and analyze the latest customer support interaction data (tickets, feedback, call logs) 
        focusing on the last quarter. Identify the top 3-5 recurring issues, quantify their frequency 
        and impact (e.g., resolution time, customer sentiment). Use the Customer Support Data Fetcher tool."""
    ),
    expected_output=(
        """A summary report detailing the key findings from the customer support data analysis, including:
- Top 3-5 recurring issues with frequency.
- Average resolution times for these issues.
- Key customer pain points mentioned in feedback.
- Any notable trends in sentiment or support agent observations."""
    ),
    agent=data_analyst # Assign task to the data_analyst agent
)

# Task 2: Identify Bottlenecks and Suggest Improvements
optimization_task = Task(
    description=(
        """Based on the data analysis report provided by the Data Analyst, identify the primary bottlenecks 
        in the support processes contributing to the identified issues (especially the top recurring ones). 
        Propose 2-3 concrete, actionable process improvements to address these bottlenecks. 
        Consider potential impact and ease of implementation."""
    ),
    expected_output=(
        """A concise list identifying the main process bottlenecks (e.g., lack of documentation for agents, 
        complex escalation path, UI issues) linked to the key problems. 
A list of 2-3 specific, actionable recommendations for process improvement 
(e.g., update agent knowledge base, simplify password reset UI, implement proactive monitoring)."""
    ),
    agent=process_optimizer # Assign task to the process_optimizer agent
    # This task implicitly uses the output of analysis_task as context
)

# Task 3: Compile COO Report
report_task = Task(
    description=(
        """Compile the findings from the Data Analyst and the recommendations from the Process Optimization Specialist 
        into a single, concise executive report for the COO. The report should clearly state:
1. The most critical customer support issues identified (with brief data points).
2. The key process bottlenecks causing these issues.
3. The recommended process improvements.
Ensure the report is easy to understand, focuses on actionable insights, and is formatted professionally."""
    ),
    expected_output=(
        """A well-structured executive report (max 1 page) summarizing the critical support issues, 
        underlying process bottlenecks, and clear, actionable recommendations for the COO. 
        Use clear headings and bullet points."""
    ),
    agent=report_writer # Assign task to the report_writer agent
)

Crew

The Crew brings the agents and tasks together, defining the workflow process (e.g., sequential).

from crewai import Crew, Process

# Define the crew with agents, tasks, and process
support_analysis_crew = Crew(
    agents=[data_analyst, process_optimizer, report_writer],
    tasks=[analysis_task, optimization_task, report_task],
    process=Process.sequential,  # Tasks will run sequentially in the order defined
    verbose=True
)

Running the Crew

Finally, kick off the crew execution with any necessary inputs.

# Start the crew's work
print("--- Starting Customer Support Analysis Crew ---")
# The 'inputs' dictionary provides initial context if needed by the first task.
# In this case, the tool simulates data fetching regardless of the input.
result = support_analysis_crew.kickoff(inputs={'data_query': 'last quarter support data'})

print("--- Crew Execution Finished ---")
print("--- Final Report for COO ---")
print(result)

The script will now execute. The Data Analyst will use the tool, the Process Optimizer will analyze the findings, and the Report Writer will compile the final report, which is then printed to the console. The verbose=True setting will show the detailed thought process and actions of each agent. 
