#!/bin/bash

# Check if the process is running
if ! pgrep -f "queue:work" > /dev/null; then
    # Start the process and redirect output

    # CRM 
    /usr/bin/php /crm/artisan queue:work \
        --queue=default,inv-send-to-client,inv-email-request-sign,verifying-client,verifying-client-parent,verifying-client-teacher,imports-student,imports-parent,imports-teacher,imports-client-event,imports-school-merge,verifying_client,verifying_client_parent,verifying_client_teacher,define-category-client,get-took-ia,send-hold-program,insert-log-client,update-raw-client,update-grade-and-graduation-year-now,email-confirmation-event \
        >> /crm/storage/logs/queue_output.log 2>&1

    # EDITING 
    /usr/bin/php /editing_v2/back-end/artisan queue:work \
        --queue=mail-assign-editor,mail-new-request,mail-cancel-assignment,mail-accept-assignment,mail-revise-essay,mail-editor-upload,mail-editor-revised,mail-completed-essay,mail-essay-comment,mail-reject-assignment \
        >> /editing_v2/back-end/storage/logs/queue_output.log 2>&1

    # STAGING CRM 
    /usr/bin/php /staging-crm/artisan queue:work \
        --queue=default,inv-send-to-client,inv-email-request-sign,verifying-client,verifying-client-parent,verifying-client-teacher,imports-student,imports-parent,imports-teacher,imports-client-event,imports-school-merge,verifying_client,verifying_client_parent,verifying_client_teacher,define-category-client,get-took-ia,send-hold-program,insert-log-client,update-raw-client,update-grade-and-graduation-year-now,email-confirmation-event \
        >> /staging-crm/storage/logs/queue_output.log 2>&1

fi
