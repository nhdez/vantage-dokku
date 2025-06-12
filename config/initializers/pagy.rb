# Pagy initializer file
# Customize pagy variables as you like
# Pagy::DEFAULT[:page]   = 1    # default page number
# Pagy::DEFAULT[:items]  = 20   # default items per page
# Pagy::DEFAULT[:size]   = 7    # default page navigation size

# Set items per page
Pagy::DEFAULT[:items] = 25

# Enable Bootstrap extra for styled pagination
require 'pagy/extras/bootstrap'

# Enable overflow extra to handle pages beyond the pagination limit
require 'pagy/extras/overflow'
Pagy::DEFAULT[:overflow] = :last_page

# Enable metadata extra to get pagination metadata
require 'pagy/extras/metadata'

# Enable trim extra to remove empty parameters from links
require 'pagy/extras/trim'