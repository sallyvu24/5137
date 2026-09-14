* There are no explicit page limits for the report. Please ensure it is concise and clear.

\=\> For example, a common mistake is adding the implementation of coding, which is not required as mentioned in the assignment specification.

* If you review the examples of multiple aggregation levels of a star schema in the seminar slides and lab exercises, you will see that the highest aggregation level should be determined by the questions provided, rather than being created arbitrarily. For example, as you mentioned, in your case (I am not referring to the assignment), if the question requires  at the month level, then the highest aggregation level for the Time dimension in your scenario should be month, rather than year. Aggregating further to the year level would remove the month-level detail required to answer the question. Therefore, when designing different aggregation versions of your star schema, always use the requirements of the provided questions to determine the appropriate grain. It is also mentioned in the assignment specification and lab exercise:

Week 3’s Pre-Data Warehousing: Exploring Dirty Data introduces five types of data problems:

* Duplication Problems  
* Relationship Problems  
* Inconsistent Values  
* Incorrect Values  
* Null Value Problems

I would like to clarify whether the data errors we identify in C2 must be strictly classified according to these five categories.  
Or are these five categories provided as the main examples/framework in Week 3, meaning that during the exploration and data cleaning of the operational database, if we identify other types of data errors, can we report them as other types of data errors, provided that we can demonstrate the issue using SQL and clearly explain:

1. Why we consider it a data error;  
2. How it affects the accuracy, integrity, or usefulness of the Data Warehouse;  
3. Why the selected data cleaning method is appropriate?

\=\> Answer: ***can we report them as other types of data errors?***  
Yes, you can. You are not limited to these 5 categories, and you may identify additional types of data errors during your exploration.

Data Cleaning  
For the **data cleaning section**, please ensure you provide a **detailed justification** for each error you identify. This should include: **(1) Why you believe it is an error**: Explain the specific issue in the data (e.g., inconsistency, duplication, incorrect value, or logical conflict). **(2) Relevance to this data warehouse project**: Clarify how the error impacts the accuracy, integrity, or usefulness of the warehouse data. **(3) Correction method and rationale**: Clearly describe the method you chose to correct the error, along with the reasoning behind your choice and why it is appropriate in this context. This level of explanation is important, as data errors can vary depending on the project scenario, and reviewers need to understand both your decision-making process and its justification.

Questions:  
**I've got 10 duplicates in a table, can I count that as 10 errors and consider my part of cleaning up the data to be done?**  
No, it will only be considered a data error.  
It's great that you've identified and addressed duplicates, but data cleaning involves more than just handling duplicates. Counting the 10 duplicates as errors is a good step, but it's important not to stop there. Other types of errors can still exist in your dataset, and it’s worth taking the time to look for and address them.  
It's important to address all different types of errors to ensure comprehensive data cleaning.  
**I'm not sure what is needed for the before/after of the data cleaning.**  
Answer:  
The requirement is quite clear:

* you need to show the SQL to explore the operational database and SQL of the data cleaning,  
* as well as the screenshot of data before and after data cleaning.

For more information about point 1, please check the A2 FAQ page \-\> Data Cleaning section for details of what you need to provide.  
In addition to the explanation required in Point 1, for Point 2 you must also attach screenshots that document your data cleaning process:  
Before Data Cleaning

* Provide the SQL query you used to identify the error.  
* Include a screenshot of the query results showing the error (e.g., duplicate records, null values, inconsistent data).  
* Moreover, you do not need to include queries that return no errors, as these are not relevant to your report and add unnecessary content. Please focus only on queries that demonstrate errors and the corresponding steps you took to correct them.

After Data Cleaning

* Provide the SQL query you used to fix the error (e.g., UPDATE, DELETE, or remove duplication,etc).

Include a screenshot of the query results after cleaning, showing that the issue has been resolved (e.g., empty result set after removing duplicates, corrected values, or consistent formatting).  
**If I find an error in the dataset, can I simply delete it without considering other methods?**  
Not necessarily. While deletion might sometimes be appropriate, you should carefully evaluate whether it is the best approach. Simply removing data can lead to unintended consequences, such as losing valuable records or even wiping out an entire table if the error occurs across many rows.  
For example, if you identify an attribute column that is entirely missing and decide to delete all rows containing null values, you may unintentionally remove the entire table. Similarly, in cases of inconsistent values, simply deleting the affected records could result in the loss of a large amount of valuable information. This approach would not be appropriate.  
Instead, you are expected to provide a clear justification for your chosen method. In many cases, correcting or transforming the data (rather than deleting it) will preserve the dataset’s integrity and ensure it remains useful for the data warehouse. Remember, what qualifies as an “error” can vary depending on the business requirements and the purpose of the data warehouse, so your explanation should show why you believe it is an error and why your method of handling it is valid.  
Star schema  
**Hi, I’m a little confused about the difference between C1 and C3. For C1, are we expected to identify and explain the required fact measures, dimensions, and dimension attributes for the data warehouse? Then, for C3, do we use those requirements to decide how to structure the data warehouse and draw the two required star/snowflake schema diagrams? In other words, does C1 require us to create a star schema diagram as well, or is the actual schema design and diagram only required in C3?**  
The logic is quite simple. In short, Your schemas in C3 should include all required fact measures and dimensions from C1 and, at the same time, be able to answer the analytical questions specified in C3.  
\*\*\*\*  
**C1 tells you what your data warehouse needs to contain \[Mandatory\]** , such as the required fact measures, dimensions, and dimension attributes based on the given requirements.  
For simplicity, **we directly tell you the required fact measures and dimensions in C1**. However, **you need to decide how to design your star schema appropriately**, including the structure, relationships, and level of aggregation, to ensure that your design is **free from modelling errors, such as double counting, correct aggregation level and avoids unnecessary or inefficient design**.  
**C3 is where you use these requirements to design and present your star/snowflake schemas.**  
**Are we allowed to create additional custom dimensions to support the analysis? Alternatively, can we define our own dimensions and fact measures based on our proposed data warehouse design, rather than using only those specified in the assignment requirements?**  
No,as mentioned in the assignment specification and lab exercise:  
Video presentation  
**Can I use slides instead of the report for my video presentation?**  
You can use either your report or PowerPoint slides for the five-minute video presentation.  
Please note that **slides are not a mandatory requirement** for the video presentation. If you choose to use slides, please ensure that the content presented is consistent with your submitted report.  
